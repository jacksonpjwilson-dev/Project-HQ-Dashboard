import Foundation
struct WatchPayload: Codable, Sendable {
    struct Task: Codable, Identifiable, Sendable { var id: UUID; var project: String; var title: String; var status: WorkStatus }
    struct Alert: Codable, Identifiable, Sendable { var id: UUID; var projectID: UUID; var project: String; var title: String; var health: Health; var state: IncidentState }
    var dashboard: DashboardSnapshot
    var tasks: [Task]
    var incidents: [Alert]
    var truncated: Bool? = nil
    func overallHealth(at date: Date) -> Health {
        let states = dashboard.projects.map { $0.currentHealth(at: date) }
        if let fault = states.filter({ $0.severity >= 2 }).max(by: { $0.severity < $1.severity }) { return fault }
        return truncated != true && !states.isEmpty && states.allSatisfy { $0 == .healthy } ? .healthy : .unknown
    }
    private func limited(_ value: String, bytes: Int) -> String {
        var result = "", count = 0
        for scalar in value.unicodeScalars {
            let width = String(scalar).utf8.count
            guard count + width <= bytes else { break }
            result.unicodeScalars.append(scalar); count += width
        }
        return result
    }
    func boundedData() throws -> Data {
        var copy = self
        copy.truncated = dashboard.projects.count > 20 || tasks.count > 50 || incidents.count > 50
        copy.dashboard.projects = Array(dashboard.projects.prefix(20)); copy.tasks = Array(tasks.prefix(50)); copy.incidents = Array(incidents.prefix(50))
        for index in copy.dashboard.projects.indices {
            copy.dashboard.projects[index].name = limited(copy.dashboard.projects[index].name, bytes: 160)
            copy.dashboard.projects[index].readings = copy.dashboard.projects[index].readings?.map { value in
                var result = value; result.name = limited(result.name, bytes: 128)
                if var evidence = result.evidence { evidence.explanation = limited(evidence.explanation, bytes: 256); evidence.source = limited(evidence.source, bytes: 128); result.evidence = evidence }
                return result
            }
        }
        copy.tasks = copy.tasks.map { .init(id: $0.id, project: limited($0.project, bytes: 160), title: limited($0.title, bytes: 400), status: $0.status) }
        copy.incidents = copy.incidents.map { .init(id: $0.id, projectID: $0.projectID, project: limited($0.project, bytes: 160), title: limited($0.title, bytes: 400), health: $0.health, state: $0.state) }
        let encoder = JSONEncoder()
        while true {
            let data = try encoder.encode(copy)
            if data.count < 60000 { return data }
            copy.truncated = true
            if !copy.tasks.isEmpty { copy.tasks.removeLast(max(1,copy.tasks.count / 2)) }
            else if !copy.incidents.isEmpty { copy.incidents.removeLast(max(1,copy.incidents.count / 2)) }
            else if copy.dashboard.projects.count > 1 { copy.dashboard.projects.removeLast() }
            else if !copy.dashboard.projects.isEmpty && (copy.dashboard.projects[0].readings != nil || copy.dashboard.projects[0].health != .unknown || copy.dashboard.projects[0].validUntil != nil) {
                // Incomplete coverage must never be shown as green after a payload reduction.
                copy.dashboard.projects[0].readings = nil; copy.dashboard.projects[0].health = .unknown; copy.dashboard.projects[0].validUntil = nil
            } else { throw CocoaError(.fileWriteOutOfSpace) }
        }
    }
}
