import Foundation

struct PublicOperationsResult {
    var observations: [String: OperationObservation]
    var activities: [OperationActivity]
    var agents: [DeclaredAgent]? = nil
}

enum PublicOperationsDecoder {
    static func decode(_ data: Data, feed: String, checkedAt: Date, latency: Int) throws -> PublicOperationsResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MonitoringError.invalidPayload }
        var activities: [OperationActivity] = []
        var agents: [DeclaredAgent]?
        let key: String
        let generated: Date
        let expiry: TimeInterval
        var state: ConnectionState = .healthy
        let reason: String
        if feed == "ykf" {
            guard let timestamp = object["generated"] as? String, let date = isoDate(timestamp),
                  object["rows"] is [Any], let active = object["active"] as? Bool else { throw MonitoringError.invalidPayload }
            key = "ykf.feed-observer"; generated = date; expiry = 300
            let provider = object["feed"] as? [String: Any]
            if provider?["ok"] as? Bool == false { state = .degraded }
            reason = active
                ? "Published flight snapshot fetched. Provider status and freshness apply to this publication only."
                : "Published off-shift snapshot fetched. This is not an active tracker heartbeat."
            if !active { state = .unknown }
        } else if feed == "crew-roster" {
            guard object["version"] as? Int == 2,
                  let bots = object["bots"] as? [[String: Any]],
                  bots.allSatisfy({ $0["id"] is String && $0["role"] is String })
            else { throw MonitoringError.invalidPayload }
            key = "crew.roster-observer"; generated = checkedAt; expiry = 900
            agents = bots.compactMap { bot in
                guard let id = bot["id"] as? String, let name = bot["name"] as? String,
                      let role = bot["role"] as? String else { return nil }
                return .init(id: id, name: OperationsText.sanitized(name), role: OperationsText.sanitized(role),
                             reportsTo: (bot["reportsTo"] as? String).map(OperationsText.sanitized))
            }
            reason = "Public version-2 roster is reachable (\(bots.count) declared agents). Execution and agent health are unverified."
        } else {
            guard feed == "crew-activity", let day = object["date"] as? String,
                  let time = object["generated"] as? String,
                  let items = object["items"] as? [[String: Any]] else { throw MonitoringError.invalidPayload }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "America/Toronto")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.isLenient = false
            guard let date = formatter.date(from: day + " " + time) else { throw MonitoringError.invalidPayload }
            key = "crew.activity-observer"; generated = date; expiry = 86400
            reason = "Public interaction archive fetched. Publication age is not a live agent heartbeat."
            for item in items.prefix(200) {
                guard let time = item["time"] as? String, let from = item["from"] as? String,
                      let to = item["to"] as? String, let topic = item["topic"] as? String,
                      let timestamp = formatter.date(from: day + " " + time), timestamp <= checkedAt.addingTimeInterval(60)
                else { continue }
                let actor = OperationsText.sanitized(from + " → " + to)
                let message = OperationsText.sanitized(topic)
                activities.append(.init(id: "crew|\(day)|\(time)|\(actor)|\(message)", systemID: "crew", targetID: "crew.activity-observer",
                                        timestamp: timestamp, actor: actor, message: message, state: .unknown))
            }
        }
        let observation = OperationObservation(state: state, observedAt: generated, checkedAt: checkedAt, expiry: expiry,
                                              reason: reason, source: "Public " + feed + " publication",
                                              latencyMilliseconds: latency, lastSuccess: checkedAt, lastFailure: nil)
        return .init(observations: [key: observation], activities: activities, agents: agents)
    }

    private static func isoDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string)
    }
}
