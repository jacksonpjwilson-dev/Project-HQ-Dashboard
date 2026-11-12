import Foundation
struct WatchPayload: Codable, Sendable {
    struct Task: Codable, Identifiable, Sendable { var id: UUID; var project: String; var title: String; var status: WorkStatus }
    struct Alert: Codable, Identifiable, Sendable { var id: UUID; var projectID: UUID; var project: String; var title: String; var health: Health; var state: IncidentState }
    var dashboard: DashboardSnapshot
    var tasks: [Task]
    var incidents: [Alert]
}
