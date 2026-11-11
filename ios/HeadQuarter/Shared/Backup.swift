import Foundation

struct WorkspaceBackup: Codable, Sendable {
    var version: Int = 1
    var exportedAt: Date
    var projects: [ProjectArchive]
    func validate() throws {
        guard version == 1, projects.count <= 10_000 else { throw BackupError.invalid("Unsupported backup version or too many projects") }
        var projectIDs: Set<UUID> = [], objectIDs: Set<UUID> = []
        func register(_ id: UUID) throws { guard objectIDs.insert(id).inserted else { throw BackupError.invalid("Duplicate object identifiers") } }
        for project in projects {
            guard projectIDs.insert(project.id).inserted, !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  project.name.count <= 500, (1...5).contains(project.priority), project.tasks.count <= 100_000 else { throw BackupError.invalid("Invalid project") }
            try register(project.id)
            let tasks = Set(project.tasks.map(\.id)), milestones = Set(project.milestones.map(\.id))
            guard !DependencyEngine.hasCycle(Dictionary(project.tasks.map { ($0.id, $0.dependencyIDs) }, uniquingKeysWith: { a, _ in a })) else { throw BackupError.invalid("Cyclic task dependencies") }
            for task in project.tasks {
                try register(task.id)
                guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.weight.isFinite, task.weight > 0,
                    (1...5).contains(task.priority), task.dependencyIDs.allSatisfy({ tasks.contains($0) && $0 != task.id }),
                    task.parentID.map({ tasks.contains($0) && $0 != task.id }) ?? true,
                    task.milestoneID.map({ milestones.contains($0) }) ?? true else { throw BackupError.invalid("Invalid task or missing dependency") }
                var cursor = task.parentID; var seen: Set<UUID> = [task.id]
                while let id = cursor {
                    guard seen.insert(id).inserted else { throw BackupError.invalid("Cyclic subtasks") }
                    cursor = project.tasks.first(where: { $0.id == id })?.parentID
                }
            }
            for service in project.services {
                try register(service.id)
                guard ["manual", "https", "github", "relay"].contains(service.provider), service.expiry.isFinite,
                    (60...604800).contains(service.expiry), (5...60).contains(service.timeout), (200...299).contains(service.expectedHTTPStatus) else { throw BackupError.invalid("Invalid service settings") }
            }
            for event in project.events { try register(event.id) }
            for incident in project.incidents { try register(incident.id) }
            for milestone in project.milestones { try register(milestone.id) }
        }
    }
}
struct ProjectArchive: Codable, Sendable {
    var id: UUID; var name: String; var summary: String; var icon: String; var phase: String
    var priority: Int; var order: Int; var requireAllChecks: Bool; var createdAt: Date
    var tasks: [TaskArchive]; var services: [ServiceArchive]; var events: [EventArchive]
    var incidents: [IncidentArchive]; var milestones: [MilestoneArchive]
}
struct TaskArchive: Codable, Sendable {
    var id: UUID; var title: String; var notes: String; var status: WorkStatus; var priority: Int
    var weight: Double; var assignee: String; var blocker: String; var createdAt: Date
    var plannedAt: Date?; var completedAt: Date?; var parentID: UUID?; var dependencyIDs: [UUID]; var milestoneID: UUID?
}
struct ServiceArchive: Codable, Sendable {
    var id: UUID; var name: String; var provider: String; var endpoint: String; var critical: Bool
    var timeout: Double; var expiry: Double; var evidence: Evidence?
    var lastCheckedAt: Date? = nil; var nextAllowedCheckAt: Date? = nil
    var expectedHTTPStatus: Int = 200; var requiredBodyText: String = ""
}
struct EventArchive: Codable, Sendable { var id: UUID; var kind: EventKind; var message: String; var source: String; var timestamp: Date; var serviceID: UUID? }
struct IncidentArchive: Codable, Sendable {
    var id: UUID; var serviceID: UUID; var title: String; var health: Health; var state: IncidentState
    var openedAt: Date; var updatedAt: Date; var resolvedAt: Date?; var lastNotifiedAt: Date?
}
struct MilestoneArchive: Codable, Sendable { var id: UUID; var title: String; var dueAt: Date?; var completedAt: Date? }
enum BackupError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let reason): return "Could not import backup: \(reason). No data was replaced." } }
}
// This is the original Project-HQ-Dashboard's projectHQv1 export format.
struct LegacyProject: Codable, Sendable {
    var id: Double
    var name: String
    var description: String
    var status: String
    var progress: Double
    var tasks: [LegacyTask]
}
struct LegacyTask: Codable, Sendable { var text: String; var done: Bool }
enum BackupCodec {
    static let maximumBytes = 20 * 1024 * 1024
    static func encode(_ backup: WorkspaceBackup) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }
    static func decode(_ data: Data) throws -> WorkspaceBackup {
        guard data.count <= maximumBytes else { throw BackupError.invalid("File exceeds the 20 MB import limit") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
            let legacy = try decoder.decode([LegacyProject].self, from: data)
            guard legacy.count <= 10_000 else { throw BackupError.invalid("Too many legacy projects") }
            let now = Date.now
            let backup = WorkspaceBackup(exportedAt: now, projects: legacy.enumerated().map { index, project in
                let tasks = project.tasks.map { task in
                    TaskArchive(id: UUID(), title: task.text, notes: "Imported from Project HQ", status: task.done ? .completed : .backlog, priority: 2, weight: 1, assignee: "", blocker: "", createdAt: now, plannedAt: nil, completedAt: nil, parentID: nil, dependencyIDs: [], milestoneID: nil)
                }
                let note = "Imported legacy project #\(project.id.formatted()). Previous phase: \(project.status). Previous manual progress: \(project.progress.formatted())%. Native progress is calculated from imported tasks. Historical completion dates were not recorded."
                return ProjectArchive(id: UUID(), name: project.name, summary: project.description, icon: "square.stack.3d.up", phase: project.status == "In development" ? "Implementation" : project.status == "Complete" ? "Release" : "Planning", priority: 2, order: index, requireAllChecks: true, createdAt: now, tasks: tasks, services: [], events: [.init(id: UUID(), kind: .manualReport, message: note, source: "Legacy backup import", timestamp: now, serviceID: nil)], incidents: [], milestones: [])
            })
            try backup.validate(); return backup
        }
        let backup = try decoder.decode(WorkspaceBackup.self, from: data)
        try backup.validate(); return backup
    }
}
