import Foundation

enum ConnectionState: String, Codable, CaseIterable, Identifiable, Sendable {
    case healthy, degraded, failed, missing, unknown, disabled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .failed: return "Failed"
        case .missing: return "Missing"
        case .unknown: return "Unknown"
        case .disabled: return "Disabled"
        }
    }
    var symbol: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .missing: return "link.badge.plus"
        case .unknown: return "questionmark.circle"
        case .disabled: return "pause.circle"
        }
    }
}

enum FlowDomain: String, Codable, CaseIterable, Identifiable {
    case runtime, development
    var id: String { rawValue }
}

struct OperationNode: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var kind: String
    var owner: String
    var purpose: String
    var source: String
    var setup: String
    var lane: Int
    var required: Bool
    var disabledReason: String?
}

struct OperationEdge: Codable, Identifiable, Equatable {
    var id: String
    var from: String
    var to: String
    var operation: String
    var owner: String
    var impact: String
    var domain: FlowDomain
}

struct SystemDefinition: Codable, Identifiable {
    var id: String
    var name: String
    var aliases: [String]
    var asset: String
    var theme: String
    var summary: String
    var repository: String
    var nodes: [OperationNode]
    var edges: [OperationEdge]

    func matches(_ name: String) -> Bool {
        ([self.name] + aliases).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

enum EcosystemRegistry {
    static func decode(_ data: Data) throws -> [SystemDefinition] {
        let systems = try JSONDecoder().decode([SystemDefinition].self, from: data)
        guard Set(systems.map(\.id)).count == systems.count else { throw RegistryError.duplicateIdentifier }
        for system in systems {
            let ids = Set(system.nodes.map(\.id))
            guard ids.count == system.nodes.count,
                  Set(system.edges.map(\.id)).count == system.edges.count,
                  system.nodes.allSatisfy({ !$0.owner.isEmpty && !$0.source.isEmpty && (0...2).contains($0.lane) }),
                  system.edges.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && !$0.owner.isEmpty })
            else { throw RegistryError.invalidGraph }
        }
        return systems
    }

    static func load() throws -> [SystemDefinition] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "ecosystem", withExtension: "json") else { throw RegistryError.missingManifest }
        return try decode(Data(contentsOf: url))
    }

    enum RegistryError: Error { case duplicateIdentifier, invalidGraph, missingManifest }
}

struct OperationObservation: Codable, Equatable {
    var state: ConnectionState
    var observedAt: Date
    var checkedAt: Date
    var expiry: TimeInterval
    var reason: String
    var source: String
    var latencyMilliseconds: Int?
    var lastSuccess: Date?
    var lastFailure: Date?

    func currentState(at now: Date) -> ConnectionState {
        guard observedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(observedAt) <= max(60, expiry)
        else { return .unknown }
        return state
    }

    func explanation(at now: Date) -> String {
        currentState(at: now) == .unknown && state != .unknown
            ? "Evidence is stale or its timestamp is invalid. " + reason
            : reason
    }
}

struct OperationActivity: Codable, Identifiable, Equatable {
    var id: String
    var systemID: String
    var targetID: String
    var timestamp: Date
    var actor: String
    var message: String
    var state: ConnectionState
}

struct DeclaredAgent: Codable, Identifiable {
    var id: String
    var name: String
    var role: String
    var reportsTo: String?
}

struct OperationsCache: Codable {
    var observations: [String: OperationObservation] = [:]
    var activities: [OperationActivity] = []
    var lastRefresh: Date?
    var agents: [DeclaredAgent]?
}

enum OperationsHealth {
    static func aggregate(_ states: [ConnectionState]) -> ConnectionState {
        if states.contains(.failed) { return .failed }
        if states.contains(.degraded) { return .degraded }
        if states.contains(.missing) { return .missing }
        if states.isEmpty || states.contains(.unknown) { return .unknown }
        if states.allSatisfy({ $0 == .disabled }) { return .disabled }
        return .healthy
    }

    static func state(_ health: Health) -> ConnectionState {
        switch health {
        case .healthy: return .healthy
        case .needsHelp: return .degraded
        case .error, .down: return .failed
        case .unknown: return .unknown
        }
    }

    static func downstream(of nodeID: String, edges: [OperationEdge]) -> Set<String> {
        var result = Set<String>()
        var queue = [nodeID]
        while let current = queue.popLast() {
            for edge in edges where edge.from == current && edge.domain == .runtime {
                if edge.to != nodeID, result.insert(edge.to).inserted { queue.append(edge.to) }
            }
        }
        return result
    }
}

enum OperationsText {
    static func sanitized(_ text: String) -> String {
        let limited = String(text.prefix(1200))
        let patterns = [
            #"(?i)(bearer\s+)[^\s]+"#,
            #"(?i)((?:token|secret|password|api_key)\s*[=:]\s*)[^\s&,]+"#,
            #"(?i)(https?://)[^\s/@]+:[^\s/@]+@"#
        ]
        let withoutQueries = limited.replacingOccurrences(of: #"(https?://[^\s?]+)\?[^\s]+"#,
                                                         with: "$1?[redacted]", options: .regularExpression)
        return patterns.reduce(withoutQueries) { value, pattern in
            value.replacingOccurrences(of: pattern, with: "$1[redacted]", options: .regularExpression)
        }
    }
}
