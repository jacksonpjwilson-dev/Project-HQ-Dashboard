import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
@MainActor enum BackupService {
    static func export(_ projects: [Project]) throws -> Data {
        try BackupCodec.encode(.init(exportedAt: .now, projects: projects.map { p in
            ProjectArchive(id: p.id, name: p.name, summary: p.summary, icon: p.icon, phase: p.phase, priority: p.priority, order: p.order, requireAllChecks: p.requireAllChecks, createdAt: p.createdAt,
                tasks: p.tasks.map { t in TaskArchive(id: t.id, title: t.title, notes: t.notes, status: t.status, priority: t.priority, weight: t.weight, assignee: t.assignee, blocker: t.blocker, createdAt: t.createdAt, plannedAt: t.plannedAt, completedAt: t.completedAt, parentID: t.parentID, dependencyIDs: t.dependencyIDs, milestoneID: t.milestoneID, modifiedAt: t.modifiedAt) },
                services: p.services.map { s in ServiceArchive(id: s.id, name: s.name, provider: s.provider, endpoint: s.endpoint, critical: s.critical, timeout: s.timeout, expiry: s.expiry, evidence: s.evidence, lastCheckedAt: s.lastCheckedAt, nextAllowedCheckAt: s.nextAllowedCheckAt, expectedHTTPStatus: s.expectedHTTPStatus, requiredBodyText: s.requiredBodyText) },
                events: p.events.map { e in EventArchive(id: e.id, kind: e.kind, message: e.message, source: e.source, timestamp: e.timestamp, serviceID: e.serviceID) },
                incidents: p.incidents.map { i in IncidentArchive(id: i.id, serviceID: i.serviceID, title: i.title, health: i.health, state: i.state, openedAt: i.openedAt, updatedAt: i.updatedAt, resolvedAt: i.resolvedAt, lastNotifiedAt: i.lastNotifiedAt) },
                milestones: p.milestones.map { m in MilestoneArchive(id: m.id, title: m.title, dueAt: m.dueAt, completedAt: m.completedAt) })
        }))
    }
    static func restore(_ backup: WorkspaceBackup, store: AppStore) -> Bool {
        func identifiers(_ project: Project) -> [UUID] {
            var ids = [project.id]
            ids.append(contentsOf: project.tasks.map(\.id)); ids.append(contentsOf: project.services.map(\.id))
            ids.append(contentsOf: project.events.map(\.id)); ids.append(contentsOf: project.incidents.map(\.id))
            ids.append(contentsOf: project.milestones.map(\.id)); return ids
        }
        let existing = Set(store.projects.flatMap(identifiers))
        let incoming = Set(backup.projects.flatMap { p -> [UUID] in
            var ids = [p.id]
            ids.append(contentsOf: p.tasks.map(\.id)); ids.append(contentsOf: p.services.map(\.id))
            ids.append(contentsOf: p.events.map(\.id)); ids.append(contentsOf: p.incidents.map(\.id))
            ids.append(contentsOf: p.milestones.map(\.id)); return ids
        })
        guard existing.isDisjoint(with: incoming) else { store.errorMessage = "This backup contains projects or child records already present on this device. Import is additive and never overwrites projects. Remove the corresponding project first if you intend to restore it."; return false }
        return store.commit {
            try backup.validate()
            for p in backup.projects {
                let project = Project(name: p.name, summary: p.summary, icon: p.icon, order: p.order)
                project.id = p.id; project.phase = p.phase; project.priority = p.priority; project.requireAllChecks = p.requireAllChecks; project.createdAt = p.createdAt
                project.tasks = p.tasks.map { t in
                    let task = WorkItem(title: t.title); task.id = t.id; task.notes = t.notes; task.status = t.status; task.priority = t.priority
                    task.weight = t.weight; task.assignee = t.assignee; task.blocker = t.blocker; task.createdAt = t.createdAt
                    task.plannedAt = t.plannedAt; task.completedAt = t.completedAt; task.parentID = t.parentID; task.dependencyIDs = t.dependencyIDs; task.milestoneID = t.milestoneID; task.modifiedAt = t.modifiedAt
                    return task
                }
                project.services = p.services.map { s in
                    let service = MonitoredService(name: s.name, provider: s.provider, endpoint: s.endpoint, expiry: s.expiry)
                    service.id = s.id; service.critical = s.critical; service.timeout = s.timeout; service.evidence = s.evidence; service.lastCheckedAt = s.lastCheckedAt; service.nextAllowedCheckAt = s.nextAllowedCheckAt; service.expectedHTTPStatus = s.expectedHTTPStatus; service.requiredBodyText = s.requiredBodyText; return service
                }
                project.events = p.events.map { e in
                    let event = ActivityEvent(kind: e.kind, message: e.message, source: e.source, serviceID: e.serviceID); event.id = e.id; event.timestamp = e.timestamp; return event
                }
                project.incidents = p.incidents.map { i in
                    let incident = Incident(serviceID: i.serviceID, title: i.title, health: i.health); incident.id = i.id; incident.stateRaw = i.state.rawValue
                    incident.openedAt = i.openedAt; incident.updatedAt = i.updatedAt; incident.resolvedAt = i.resolvedAt; incident.lastNotifiedAt = i.lastNotifiedAt; return incident
                }
                project.milestones = p.milestones.map { m in let milestone = Milestone(title: m.title); milestone.id = m.id; milestone.dueAt = m.dueAt; milestone.completedAt = m.completedAt; return milestone }
                store.context.insert(project)
            }
        }
    }
}
