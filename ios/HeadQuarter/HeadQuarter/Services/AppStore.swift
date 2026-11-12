import Foundation
import SwiftData
import SwiftUI
import WidgetKit
import Observation

@MainActor @Observable final class AppStore {
    let container: ModelContainer
    let isDemo: Bool
    var errorMessage: String?
    var isRefreshing = false
    private var notificationsInFlight: Set<UUID> = []
    var selectedTab = 0
    var projectPath: [UUID] = []
    var showOnlyErrors = false
    var showOnlyHelp = false
    var showOnlyActive = false
    let operations = LiveOperations()
    var context: ModelContext { container.mainContext }
    var projects: [Project] {
        do { return try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.order), SortDescriptor(\Project.name)])) }
        catch { errorMessage = error.localizedDescription; return [] }
    }
    init(container: ModelContainer, isDemo: Bool = false) { self.container = container; self.isDemo = isDemo }
    @discardableResult func commit(_ changes: () throws -> Void) -> Bool {
        do { try changes(); try context.save() }
        catch { context.rollback(); errorMessage = "Your change was not saved: \(error.localizedDescription)"; return false }
        publishSnapshot()
        return true
    }
    func publishSnapshot() {
        guard !isDemo else { return }
        let now = Date.now
        var snapshot = DashboardSnapshot(generatedAt: now, projects: projects.map { project in
            let health = project.health(at: now)
            let validUntil = project.services.compactMap { service in service.evidence.map { $0.observedAt.addingTimeInterval(max(60, service.expiry)) } }.min()
            return ProjectSnapshot(id: project.id, name: project.name, health: health.state, progress: project.progress,
                alerts: project.activeIncidents.count, evidenceAt: health.observedAt, validUntil: validUntil,
                readings: project.services.map(\.reading), requireAllChecks: project.requireAllChecks)
        })
        snapshot.overallProgress = ProgressEngine.completion(projects.flatMap(\.tasks).map { .init(weight: $0.weight, completed: $0.status == .completed) })
        do { try SharedStorage.save(snapshot); WidgetCenter.shared.reloadAllTimelines() }
        catch { errorMessage = "App data was saved, but widget sharing failed: \(error.localizedDescription)" }
    }
    func addProject(name: String, summary: String, icon: String) -> Bool {
        commit { context.insert(Project(name: name, summary: summary, icon: icon, order: (projects.map(\.order).max() ?? -1) + 1)) }
    }
    func removeProject(_ project: Project) -> Bool {
        let projectID = project.id
        var credentials: [UUID: String] = [:]
        do {
            if !isDemo {
                for service in project.services { if let token = try CredentialVault.read(service.id) { credentials[service.id] = token } }
                for id in credentials.keys { try CredentialVault.set("", for: id) }
            }
            let saved = commit { context.delete(project) }
            if !saved { try restoreCredentials(credentials) }
            else { Task { await operations.end(projectID: projectID) } }
            return saved
        } catch {
            do { try restoreCredentials(credentials) } catch { errorMessage = "Deletion stopped. Credential recovery failed; re-enter the affected service tokens."; return false }
            errorMessage = "Deletion stopped: \(error.localizedDescription)"; return false
        }
    }
    func removeService(_ service: MonitoredService, in project: Project) -> Bool {
        let id = service.id
        var credentials: [UUID: String] = [:]
        do {
            if !isDemo, let token = try CredentialVault.read(id) { credentials[id] = token; try CredentialVault.set("", for: id) }
            let saved = commit { project.services.removeAll { $0.id == id }; context.delete(service) }
            if !saved { try restoreCredentials(credentials) }
            return saved
        } catch {
            do { try restoreCredentials(credentials) } catch { errorMessage = "Removal stopped. Credential recovery failed; re-enter the service token."; return false }
            errorMessage = "Removal stopped: \(error.localizedDescription)"; return false
        }
    }
    private func restoreCredentials(_ credentials: [UUID: String]) throws {
        for (id, token) in credentials { try CredentialVault.set(token, for: id) }
    }
    func record(_ evidence: Evidence, for service: MonitoredService, in project: Project, kind: EventKind = .manualReport) {
        let old = service.evidence
        // Providers may return the same workflow repeatedly. Do not manufacture activity or repeat incidents.
        guard old != evidence else { _ = commit { service.lastCheckedAt = .now }; return }
        let current = HealthEngine.evaluate(.init(name: service.name, critical: service.critical, expiry: service.expiry, evidence: evidence))
        var notification: Incident?
        var recovered: [Incident] = []
        let saved = commit {
            service.evidence = evidence; service.lastCheckedAt = .now
            let event = ActivityEvent(kind: kind, message: evidence.explanation, source: evidence.source, serviceID: service.id)
            event.timestamp = min(evidence.observedAt, .now); project.events.append(event)
            let existing = project.incidents.first { $0.serviceID == service.id && $0.state != .resolved }
            if current.state.severity >= Health.needsHelp.severity {
                if let existing {
                    if current.state.severity > existing.health.severity { existing.lastNotifiedAt = nil }
                    existing.healthRaw = current.state.rawValue; existing.title = current.explanation; existing.updatedAt = .now
                    notification = existing
                } else {
                    let incident = Incident(serviceID: service.id, title: current.explanation, health: current.state)
                    project.incidents.append(incident); notification = incident
                }
            } else if current.state == .healthy {
                recovered = project.incidents.filter { $0.serviceID == service.id && $0.state != .resolved }
                for incident in recovered { incident.transition(to: .resolved) }
                if !recovered.isEmpty {
                    project.events.append(ActivityEvent(kind: .serviceRecovered, message: "\(service.name) recovered", source: evidence.source, serviceID: service.id))
                }
            }
        }
        guard saved, !isDemo else { return }
        let projectID = project.id, projectName = project.name
        if let incident = notification, incident.lastNotifiedAt == nil, incident.state == .open,
           notificationsInFlight.insert(incident.id).inserted {
            Task { @MainActor in
                defer { notificationsInFlight.remove(incident.id) }
                guard incident.state == .open else { return }
                do {
                    if try await AlertService.shared.send(id: incident.id.uuidString, title: projectName, message: incident.title,
                        severity: incident.health.severity, category: kind == .buildFailed ? "build" : "incident", projectID: projectID, incidentID: incident.id) {
                        _ = commit { incident.lastNotifiedAt = .now }
                    }
                } catch { errorMessage = "Report saved; notification failed: \(error.localizedDescription)" }
            }
        }
        for incident in recovered {
            Task {
                do { _ = try await AlertService.shared.send(id: "recovery-\(incident.id)", title: "\(projectName) recovered", message: evidence.explanation, severity: 4, category: "recovery", projectID: projectID) }
                catch { errorMessage = "Recovery saved; notification failed: \(error.localizedDescription)" }
            }
        }
    }

    func check(_ service: MonitoredService, in project: Project) async {
        guard !isDemo, service.provider != "manual", (service.nextAllowedCheckAt ?? .distantPast) <= .now else { return }
        let projectID = project.id, serviceID = service.id, providerID = service.provider, endpoint = service.endpoint, revision = service.configurationRevision
        func currentConnection() -> (Project, MonitoredService)? {
            guard let p = projects.first(where: { $0.id == projectID }),
                  let s = p.services.first(where: { $0.id == serviceID && $0.provider == providerID && $0.endpoint == endpoint && $0.configurationRevision == revision }) else { return nil }
            return (p, s)
        }
        do {
            let configuration = MonitorConfiguration(id: serviceID, endpoint: endpoint, timeout: service.timeout, credential: try CredentialVault.read(serviceID), expectedHTTPStatus: service.expectedHTTPStatus, requiredBodyText: service.requiredBodyText)
            let provider: any MonitoringProvider
            switch providerID {
            case "https": provider = EndpointProvider()
            case "github": provider = GitHubActionsProvider()
            case "relay": provider = RelayProvider()
            default: throw MonitoringError.invalidPayload
            }
            let evidence = try await provider.check(configuration)
            guard !Task.isCancelled, let (currentProject, currentService) = currentConnection() else { return }
            if currentService.nextAllowedCheckAt != nil { _ = commit { currentService.nextAllowedCheckAt = nil } }
            let kind: EventKind = providerID == "github" ? (evidence.state == .healthy ? .buildSucceeded : evidence.state == .error ? .buildFailed : .manualReport) : (evidence.state == .healthy ? .manualReport : .healthCheckFailed)
            record(evidence, for: currentService, in: currentProject, kind: kind)
        } catch {
            guard !Task.isCancelled, let (currentProject, currentService) = currentConnection() else { return }
            if let monitorError = error as? MonitoringError, case .rateLimited(let until) = monitorError { _ = commit { currentService.nextAllowedCheckAt = until } }
            let health: Health = (error as? MonitoringError) == .authentication ? .needsHelp : .unknown
            // Device connectivity is not evidence that a remote service is down.
            record(.init(state: health, explanation: error.localizedDescription, observedAt: .now, source: "\(providerID) connection"), for: currentService, in: currentProject, kind: .integrationDisconnected)
        }
    }
    func refresh(project: Project? = nil) async {
        guard !isRefreshing, !isDemo else { return }
        isRefreshing = true; defer { isRefreshing = false; publishSnapshot() }
        let schedule = (project.map({ [$0] }) ?? projects).flatMap { p in p.services.filter { $0.provider != "manual" }.map { (p.id, $0.id) } }
        for (projectID, serviceID) in schedule {
            guard !Task.isCancelled else { return }
            if let currentProject = projects.first(where: { $0.id == projectID }), let currentService = currentProject.services.first(where: { $0.id == serviceID }) {
                await check(currentService, in: currentProject)
            }
        }
    }
    @discardableResult func saveTask(_ task: WorkItem, in project: Project, isNew: Bool,
        title: String, notes: String, status: WorkStatus, priority: Int, weight: Double,
        assignee: String, blocker: String, due: Date?, parentID: UUID?, dependencyIDs: [UUID], milestoneID: UUID?) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, weight.isFinite, weight > 0 else { errorMessage = "A task needs a title and a positive weight."; return false }
        let all = project.tasks
        let available = Set(all.filter { $0.id != task.id }.map(\.id))
        guard dependencyIDs.allSatisfy({ available.contains($0) }), parentID.map({ available.contains($0) }) ?? true,
              milestoneID.map({ id in project.milestones.contains { $0.id == id } }) ?? true else {
            errorMessage = "Select dependencies, parent tasks, and milestones from this project."; return false
        }
        if status == .completed || status.isActive {
            guard dependencyIDs.allSatisfy({ id in all.contains { $0.id == id && $0.status == .completed } }) else {
                errorMessage = "Complete all dependencies before starting or completing this task."; return false
            }
        }
        let graph = Dictionary(uniqueKeysWithValues: all.filter { $0.id != task.id }.map { ($0.id, $0.dependencyIDs) })
            .merging([task.id: dependencyIDs]) { _, new in new }
        if DependencyEngine.hasCycle(graph) { errorMessage = "Task dependencies cannot contain a cycle."; return false }
        if let parentID {
            var cursor: UUID? = parentID; var seen: Set<UUID> = [task.id]
            while let id = cursor {
                guard seen.insert(id).inserted else { errorMessage = "Subtasks cannot contain a parent cycle."; return false }
                cursor = all.first(where: { $0.id == id })?.parentID
            }
        }
        let previous = task.status
        let saved = commit {
            task.title = title; task.notes = notes; task.status = status; task.priority = priority; task.weight = weight
            task.assignee = assignee; task.blocker = blocker; task.plannedAt = due; task.parentID = parentID
            task.dependencyIDs = dependencyIDs; task.milestoneID = milestoneID
            task.completedAt = status == .completed ? (task.completedAt ?? .now) : nil
            if isNew { project.tasks.append(task) }
            if isNew || previous != status {
                let kind: EventKind = status == .completed ? .taskCompleted : status == .failed ? .taskFailed : status == .blocked ? .approvalRequired : status.isActive ? .taskStarted : .manualReport
                project.events.append(ActivityEvent(kind: kind, message: "\(title): \(status.rawValue)", source: "Manual task update"))
            }
            updateMilestones(project)
        }
        if saved {
            Task { await operations.update(task: task) }
            if !isDemo, (isNew || previous != status), status == .blocked || status == .failed {
                let message = blocker.isEmpty ? "\(title): \(status.rawValue)" : "\(title): \(blocker)"
                Task {
                    do { _ = try await AlertService.shared.send(id: "task-\(task.id)-\(status.rawValue)-\(Date.now.timeIntervalSince1970)", title: project.name, message: message, severity: status == .failed ? 3 : 2, projectID: project.id) }
                    catch { errorMessage = "Task saved; notification failed: \(error.localizedDescription)" }
                }
            }
        }
        return saved
    }
    private func updateMilestones(_ project: Project) {
        for milestone in project.milestones {
            let tasks = project.tasks.filter { $0.milestoneID == milestone.id }
            let complete = !tasks.isEmpty && tasks.allSatisfy { $0.status == .completed }
            if complete, milestone.completedAt == nil {
                milestone.completedAt = .now
                project.events.append(ActivityEvent(kind: .milestoneCompleted, message: milestone.title, source: "Tracked work"))
                if !isDemo {
                    let id = "milestone-\(milestone.id)-\(Date.now.timeIntervalSince1970)"
                    Task {
                        do { _ = try await AlertService.shared.send(id: id, title: "Milestone completed", message: "\(project.name): \(milestone.title)", severity: 4, category: "milestone", projectID: project.id) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            } else if !complete { milestone.completedAt = nil }
        }
    }
    @discardableResult func deleteTask(_ task: WorkItem, in project: Project) -> Bool {
        let taskID = task.id, projectID = project.id
        let saved = commit {
            for other in project.tasks {
                other.dependencyIDs.removeAll { $0 == taskID }
                if other.parentID == taskID { other.parentID = nil }
            }
            project.tasks.removeAll { $0.id == taskID }; context.delete(task); updateMilestones(project)
        }
        if saved { Task { await operations.end(projectID: projectID, taskID: taskID) } }
        return saved
    }
    func route(_ url: URL) {
        guard url.scheme == "headquarter" else { return }
        switch url.host {
        case "project":
            guard let id = UUID(uuidString: url.lastPathComponent), projects.contains(where: { $0.id == id }) else { errorMessage = "This project is no longer available."; return }
            selectedTab = 1; projectPath = [id]
        case "help": selectedTab = 1; showOnlyHelp = true; projectPath = []
        case "tasks": selectedTab = 2; showOnlyActive = true
        case "errors": selectedTab = 3; showOnlyErrors = true
        default: selectedTab = 0
        }
    }
    static func demonstration() throws -> AppStore {
        let container = try Persistence.container(inMemory: true)
        try Persistence.seed(container.mainContext)
        let store = AppStore(container: container, isDemo: true)
        for (index, project) in store.projects.enumerated() {
            project.phase = index == 0 ? "Implementation" : "Planning"
            let task = WorkItem(title: "Example: validate first release")
            task.status = index % 2 == 0 ? .inProgress : .completed
            if task.status == .completed { task.completedAt = .now }
            project.tasks.append(task)
            let service = MonitoredService(name: "DEMO · Example heartbeat", expiry: 3600)
            service.evidence = Evidence(state: [.healthy, .needsHelp, .error, .down, .unknown][index % 5], explanation: "Simulated evidence; not connected to a real system", observedAt: .now, source: "DEMONSTRATION")
            project.services.append(service)
            if let state = service.evidence?.state, state.severity >= 2 {
                project.incidents.append(Incident(serviceID: service.id, title: "DEMO · Simulated service requires attention", health: state))
            }
        }
        try container.mainContext.save()
        return store
    }
}
