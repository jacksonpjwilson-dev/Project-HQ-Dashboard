import Foundation
import SwiftData

@Model final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var icon: String
    var phase: String
    var priority: Int
    var order: Int
    var requireAllChecks: Bool
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var tasks: [WorkItem] = []
    @Relationship(deleteRule: .cascade) var services: [MonitoredService] = []
    @Relationship(deleteRule: .cascade) var events: [ActivityEvent] = []
    @Relationship(deleteRule: .cascade) var incidents: [Incident] = []
    @Relationship(deleteRule: .cascade) var milestones: [Milestone] = []
    init(name: String, summary: String, icon: String = "square.stack.3d.up", order: Int = 0) {
        id = UUID(); self.name = name; self.summary = summary; self.icon = icon
        phase = "Planning"; priority = 2; self.order = order; requireAllChecks = true; createdAt = .now
    }
    var progress: Double { ProgressEngine.completion(tasks.map { .init(weight: $0.weight, completed: $0.status == .completed) }) }
    func health(at now: Date = .now) -> HealthResult { HealthEngine.aggregate(services.map(\.reading), now: now, requireAll: requireAllChecks) }
    var activeIncidents: [Incident] { incidents.filter { $0.state != .resolved } }
    var requiresAttention: Bool {
        health().state.severity >= Health.needsHelp.severity || !activeIncidents.isEmpty || tasks.contains { $0.status == .blocked || $0.status == .failed }
    }
}
@Model final class WorkItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var statusRaw: String
    var priority: Int
    var weight: Double
    var assignee: String
    var blocker: String
    var createdAt: Date
    var plannedAt: Date?
    var completedAt: Date?
    var parentID: UUID?
    var dependencyIDs: [UUID]
    var milestoneID: UUID?
    var modifiedAt: Date?
    init(title: String) {
        id = UUID(); self.title = title; notes = ""; statusRaw = WorkStatus.backlog.rawValue
        priority = 2; weight = 1; assignee = ""; blocker = ""; createdAt = .now; modifiedAt = .now; dependencyIDs = []
    }
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .backlog }
        set { statusRaw = newValue.rawValue }
    }
}
@Model final class MonitoredService {
    @Attribute(.unique) var id: UUID
    var name: String
    var provider: String
    var endpoint: String
    var critical: Bool
    var timeout: Double
    var expiry: Double
    var evidenceData: Data?
    var lastCheckedAt: Date?
    var nextAllowedCheckAt: Date?
    var expectedHTTPStatus: Int = 200
    var requiredBodyText: String = ""
    var timestampPath: String = ""
    var configurationRevision: Int = 0
    init(name: String, provider: String = "manual", endpoint: String = "", expiry: Double = 3600) {
        id = UUID(); self.name = name; self.provider = provider; self.endpoint = endpoint
        critical = true; timeout = 15; self.expiry = expiry
    }
    var evidence: Evidence? {
        get { evidenceData.flatMap { try? JSONDecoder().decode(Evidence.self, from: $0) } }
        set { evidenceData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
    var reading: ServiceReading { .init(name: name, critical: critical, expiry: expiry, evidence: evidence) }
}
@Model final class ActivityEvent {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var message: String
    var source: String
    var timestamp: Date
    var serviceID: UUID?
    init(kind: EventKind, message: String, source: String, serviceID: UUID? = nil) {
        id = UUID(); kindRaw = kind.rawValue; self.message = message; self.source = source
        timestamp = .now; self.serviceID = serviceID
    }
    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .manualReport }
}
@Model final class Incident {
    @Attribute(.unique) var id: UUID
    var serviceID: UUID
    var title: String
    var healthRaw: String
    var stateRaw: String
    var openedAt: Date
    var updatedAt: Date
    var resolvedAt: Date?
    var lastNotifiedAt: Date?
    init(serviceID: UUID, title: String, health: Health) {
        id = UUID(); self.serviceID = serviceID; self.title = title; healthRaw = health.rawValue
        stateRaw = IncidentState.open.rawValue; openedAt = .now; updatedAt = .now
    }
    var state: IncidentState { IncidentState(rawValue: stateRaw) ?? .open }
    var health: Health { Health(rawValue: healthRaw) ?? .unknown }
    @discardableResult func transition(to next: IncidentState) -> Bool {
        guard state.canTransition(to: next) else { return false }
        stateRaw = next.rawValue; updatedAt = .now
        if next == .resolved { resolvedAt = .now }
        return true
    }
}
@Model final class Milestone {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueAt: Date?
    var completedAt: Date?
    init(title: String) { id = UUID(); self.title = title }
}
@Model final class WorkspaceConfiguration {
    @Attribute(.unique) var key: String
    var hasSeeded: Bool
    init() { key = "workspace"; hasSeeded = true }
}
@Model final class RepositoryCache {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var payload: Data?
    var errorMessage: String?
    var errorAt: Date?
    init(id: UUID, projectID: UUID) { self.id = id; self.projectID = projectID }
    var activity: RepositoryActivity? {
        get { payload.flatMap { try? JSONDecoder().decode(RepositoryActivity.self, from: $0) } }
        set { payload = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
@MainActor enum Persistence {
    private static var sharedContainer: ModelContainer?
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory, let sharedContainer { return sharedContainer }
        let schema = Schema([Project.self, WorkItem.self, MonitoredService.self, ActivityEvent.self, Incident.self, Milestone.self, WorkspaceConfiguration.self, RepositoryCache.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, groupContainer: .none, cloudKitDatabase: .none)])
        if !inMemory { sharedContainer = container }; return container
    }
    @MainActor static func seed(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<WorkspaceConfiguration>()) == 0 else { return }
        if try context.fetchCount(FetchDescriptor<Project>()) > 0 {
            context.insert(WorkspaceConfiguration()); try context.save(); return
        }
        let initial: [(String, String, String)] = [
            ("Logbook", "Fitness, nutrition, sleep, and workout tracking", "figure.strengthtraining.traditional"),
            ("Daily Briefing", "Personalized information and automated updates", "sun.horizon"),
            ("Stack", "Personal finance and transaction tracking", "creditcard"),
            ("Crew", "Customizable personal dashboard", "square.grid.2x2"),
            ("YKF Arrivals", "Airport arrivals and flight monitoring", "airplane.arrival"),
            ("Pantry", "Grocery and food inventory management", "carrot"),
            ("Head Quarter", "Development and system operations command centre", "building.2")]
        for (index, item) in initial.enumerated() { context.insert(Project(name: item.0, summary: item.1, icon: item.2, order: index)) }
        context.insert(WorkspaceConfiguration())
        try context.save()
    }
}
