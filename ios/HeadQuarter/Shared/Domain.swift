import Foundation

enum Health: String, Codable, CaseIterable, Identifiable, Sendable {
    case healthy, needsHelp, error, down, unknown
    var id: String { rawValue }
    var label: String {
        switch self {
        case .healthy: return "Running Smoothly"
        case .needsHelp: return "Needs Help"
        case .error: return "Error"
        case .down: return "Down"
        case .unknown: return "Unknown / Not Configured"
        }
    }
    var symbol: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .needsHelp: return "hand.raised.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .down: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    var severity: Int {
        switch self { case .unknown: return 0; case .healthy: return 1; case .needsHelp: return 2; case .error: return 3; case .down: return 4 }
    }
}
enum WorkStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case backlog = "Backlog", ready = "Ready", inProgress = "In Progress", blocked = "Blocked"
    case testing = "Testing", completed = "Completed", failed = "Failed"
    var id: String { rawValue }
    var isActive: Bool { self == .inProgress || self == .testing }
}
enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case taskStarted, taskCompleted, taskFailed, buildSucceeded, buildFailed, deploymentCompleted
    case integrationDisconnected, healthCheckFailed, serviceRecovered, approvalRequired, manualReport, milestoneCompleted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .taskStarted: return "Task started"
        case .taskCompleted: return "Task completed"
        case .taskFailed: return "Task failed"
        case .buildSucceeded: return "Build succeeded"
        case .buildFailed: return "Build failed"
        case .deploymentCompleted: return "Deployment completed"
        case .integrationDisconnected: return "Integration disconnected"
        case .healthCheckFailed: return "Health check failed"
        case .serviceRecovered: return "Service recovered"
        case .approvalRequired: return "Approval required"
        case .manualReport: return "Manual report"
        case .milestoneCompleted: return "Milestone completed"
        }
    }
}
struct Evidence: Codable, Equatable, Sendable {
    var state: Health
    var explanation: String
    var observedAt: Date
    var source: String
}
struct HealthResult: Equatable, Sendable {
    var state: Health
    var explanation: String
    var observedAt: Date?
}
struct ServiceReading: Sendable {
    var name: String
    var critical: Bool
    var expiry: TimeInterval
    var evidence: Evidence?
}
enum HealthEngine {
    static func evaluate(_ reading: ServiceReading, now: Date = .now) -> HealthResult {
        guard let evidence = reading.evidence else {
            return .init(state: .unknown, explanation: "\(reading.name): no monitoring evidence", observedAt: nil)
        }
        guard !evidence.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !evidence.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(state: .unknown, explanation: "\(reading.name): monitoring evidence is incomplete", observedAt: evidence.observedAt)
        }
        guard evidence.observedAt <= now.addingTimeInterval(60), now.timeIntervalSince(evidence.observedAt) <= max(60, reading.expiry) else {
            return .init(state: .unknown, explanation: "\(reading.name): evidence is stale or timestamp is invalid", observedAt: evidence.observedAt)
        }
        let state: Health = evidence.state == .down && !reading.critical ? .error : evidence.state
        return .init(state: state, explanation: "\(reading.name): \(evidence.explanation) [\(evidence.source)]", observedAt: evidence.observedAt)
    }
    // Confirmed failures take precedence; incomplete coverage prevents an all-green result.
    static func aggregate(_ readings: [ServiceReading], now: Date = .now, requireAll: Bool = true) -> HealthResult {
        let results = readings.map { evaluate($0, now: now) }
        guard !results.isEmpty else { return .init(state: .unknown, explanation: "No services configured", observedAt: nil) }
        let faults = results.filter { $0.state.severity >= Health.needsHelp.severity }
        if let worst = faults.max(by: { $0.state.severity < $1.state.severity }) { return worst }
        if requireAll, let unknown = results.first(where: { $0.state == .unknown }) { return unknown }
        if let healthy = results.first(where: { $0.state == .healthy }) {
            return .init(state: .healthy, explanation: requireAll ? "All configured checks have fresh passing evidence" : "Available checks pass; incomplete coverage is allowed by project settings", observedAt: healthy.observedAt)
        }
        return results[0]
    }
}
struct WeightedWork: Sendable { var weight: Double; var completed: Bool }
enum ProgressEngine {
    static func completion(_ work: [WeightedWork]) -> Double {
        let valid = work.filter { $0.weight.isFinite && $0.weight > 0 }
        guard let scale = valid.map(\.weight).max() else { return 0 }
        let total = valid.reduce(0) { $0 + $1.weight / scale }
        return valid.filter(\.completed).reduce(0) { $0 + $1.weight / scale } / total
    }
}
enum IncidentState: String, Codable, CaseIterable, Sendable {
    case open, acknowledged, resolved
    func canTransition(to next: IncidentState) -> Bool {
        switch (self, next) {
        case (.open, .acknowledged), (.open, .resolved), (.acknowledged, .resolved): return true
        default: return false
        }
    }
}
struct ProjectSnapshot: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var health: Health
    var progress: Double
    var alerts: Int
    var evidenceAt: Date?
    var validUntil: Date?
    func currentHealth(at date: Date) -> Health {
        guard let validUntil, date <= validUntil else { return .unknown }
        return health
    }
}
struct DashboardSnapshot: Codable, Sendable {
    var generatedAt: Date
    var projects: [ProjectSnapshot]
    var overallProgress: Double = 0
    static var empty: Self { .init(generatedAt: .now, projects: []) }
}
enum SharedStorage {
    // Replace in both target entitlements when configuring your Apple signing team.
    static let group = "group.com.headquarter.app"
    static let key = "dashboard.snapshot.v1"
    static func load() -> DashboardSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DashboardSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
    static func save(_ snapshot: DashboardSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: group) else { throw CocoaError(.fileWriteNoPermission) }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    }
}

// Kahn's algorithm avoids recursion limits on large task graphs.
enum DependencyEngine {
    static func hasCycle(_ graph: [UUID: [UUID]]) -> Bool {
        var degrees: [UUID: Int] = [:], dependents: [UUID: [UUID]] = [:]
        for (id, dependencies) in graph {
            degrees[id, default: 0] += dependencies.count
            for dependency in dependencies {
                degrees[dependency, default: 0] += 0
                dependents[dependency, default: []].append(id)
            }
        }
        var queue = degrees.filter { $0.value == 0 }.map(\.key), offset = 0
        while offset < queue.count {
            let id = queue[offset]; offset += 1
            for dependent in dependents[id] ?? [] {
                degrees[dependent, default: 0] -= 1
                if degrees[dependent] == 0 { queue.append(dependent) }
            }
        }
        return queue.count != degrees.count
    }
}
