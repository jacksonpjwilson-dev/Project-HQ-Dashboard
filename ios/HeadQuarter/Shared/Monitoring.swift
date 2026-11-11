import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MonitorConfiguration: Sendable {
    var id: UUID
    var endpoint: String
    var timeout: Double
    var credential: String?
    var expectedHTTPStatus: Int = 200
    var requiredBodyText: String = ""
}
protocol MonitoringProvider: Sendable {
    func check(_ configuration: MonitorConfiguration) async throws -> Evidence
}
enum MonitoringError: LocalizedError, Equatable {
    case invalidURL, badResponse, authentication, invalidPayload
    case rateLimited(until: Date)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid HTTPS endpoint without embedded credentials."
        case .badResponse: return "The service returned an invalid HTTP response."
        case .authentication: return "Authentication failed. Update the token in service settings."
        case .rateLimited(let until): return "Rate limited. Next check after \(until.formatted(date: .omitted, time: .shortened))."
        case .invalidPayload: return "The provider returned an unsupported response."
        }
    }
}
struct EndpointProvider: MonitoringProvider {
    func check(_ configuration: MonitorConfiguration) async throws -> Evidence {
        guard let url = URL(string: configuration.endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw MonitoringError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: min(60, max(5, configuration.timeout)))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = configuration.credential { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitoringError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MonitoringError.authentication }
        if http.statusCode == 429 { throw MonitoringError.rateLimited(until: RateLimitPolicy.retryDate(headers: http.allHeaderFields, now: .now)) }
        guard data.count <= 1024 * 1024 else { throw MonitoringError.invalidPayload }
        return Self.evaluate(status: http.statusCode, body: data, configuration: configuration, source: url.host ?? "HTTPS", now: .now)
    }
    static func evaluate(status: Int, body: Data, configuration: MonitorConfiguration, source: String, now: Date) -> Evidence {
        let statusPasses = status == configuration.expectedHTTPStatus
        let bodyPasses = configuration.requiredBodyText.isEmpty || (String(data: body, encoding: .utf8)?.contains(configuration.requiredBodyText) ?? false)
        let state: Health = statusPasses && bodyPasses ? .healthy : status >= 500 ? .down : .error
        let reason = !statusPasses ? "HTTPS check returned HTTP \(status); expected \(configuration.expectedHTTPStatus)" : !bodyPasses ? "HTTP \(status) returned, but the required response text was missing" : "HTTPS criteria passed (HTTP \(status))"
        return .init(state: state, explanation: reason, observedAt: now, source: source)
    }
}
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
struct GitHubActionsProvider: MonitoringProvider {
    private struct Response: Decodable { var workflow_runs: [Run] }
    private struct Run: Decodable { var status: String; var conclusion: String?; var updated_at: Date; var name: String? }
    func check(_ configuration: MonitorConfiguration) async throws -> Evidence {
        // Configuration is owner/repository, never a user-controlled API host.
        let parts = configuration.endpoint.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && String($0).rangeOfCharacter(from: allowed.inverted) == nil }),
              let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/actions/runs?per_page=1") else { throw MonitoringError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: min(60, max(5, configuration.timeout)))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = configuration.credential { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitoringError.badResponse }
        if http.statusCode == 401 { throw MonitoringError.authentication }
        if http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") != "0" && http.value(forHTTPHeaderField: "Retry-After") == nil { throw MonitoringError.authentication }
        if http.statusCode == 429 || http.statusCode == 403 { throw MonitoringError.rateLimited(until: RateLimitPolicy.retryDate(headers: http.allHeaderFields, now: .now)) }
        guard http.statusCode == 200 else { throw MonitoringError.badResponse }
        return try Self.decodeEvidence(data)
    }
    static func decodeEvidence(_ data: Data) throws -> Evidence {
        guard data.count <= 2 * 1024 * 1024 else { throw MonitoringError.invalidPayload }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(Response.self, from: data) else { throw MonitoringError.invalidPayload }
        guard let run = result.workflow_runs.first else {
            return .init(state: .unknown, explanation: "No workflow runs found", observedAt: .now, source: "GitHub Actions")
        }
        let health: Health
        if run.status == "waiting" || run.conclusion == "action_required" { health = .needsHelp }
        else if run.status != "completed" { health = .unknown }
        else if run.conclusion == "success" { health = .healthy }
        else if ["failure", "timed_out", "startup_failure"].contains(run.conclusion ?? "") { health = .error }
        else { health = .unknown }
        // A successful old build is not fresh evidence of an operational service.
        return .init(state: health, explanation: "Latest workflow: \(run.name ?? "Build") · \(run.conclusion ?? run.status)", observedAt: run.updated_at, source: "GitHub Actions")
    }
}

struct RelayProvider: MonitoringProvider {
    func check(_ configuration: MonitorConfiguration) async throws -> Evidence {
        guard let token = configuration.credential, !token.isEmpty else { throw MonitoringError.authentication }
        guard let url = URL(string: configuration.endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw MonitoringError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: min(60, max(5, configuration.timeout)))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitoringError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MonitoringError.authentication }
        if http.statusCode == 429 { throw MonitoringError.rateLimited(until: RateLimitPolicy.retryDate(headers: http.allHeaderFields, now: .now)) }
        guard http.statusCode == 200, data.count <= 65536 else { throw MonitoringError.invalidPayload }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(RelayEvidenceEnvelope.self, from: data)
        try envelope.validate(expectedServiceID: configuration.id, now: .now)
        return envelope.evidence
    }
}
struct RelayEvidenceEnvelope: Codable, Sendable {
    var version: Int
    var serviceID: UUID
    var evidence: Evidence
    func validate(expectedServiceID: UUID, now: Date) throws {
        guard version == 1, serviceID == expectedServiceID,
              evidence.observedAt <= now.addingTimeInterval(60), !evidence.explanation.isEmpty,
              evidence.explanation.count <= 4096, !evidence.source.isEmpty, evidence.source.count <= 256 else { throw MonitoringError.invalidPayload }
    }
}

enum RateLimitPolicy {
    static func retryDate(headers: [AnyHashable: Any], now: Date) -> Date {
        let normalized = Dictionary(headers.map { (String(describing: $0.key).lowercased(), String(describing: $0.value)) }, uniquingKeysWith: { _, last in last })
        if let value = normalized["retry-after"] {
            if let seconds = Double(value), seconds.isFinite { return now.addingTimeInterval(max(60, min(seconds, 86400))) }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) { return max(now.addingTimeInterval(60), min(date, now.addingTimeInterval(86400))) }
        }
        if let value = normalized["x-ratelimit-reset"], let epoch = Double(value), epoch.isFinite {
            return max(now.addingTimeInterval(60), min(Date(timeIntervalSince1970: epoch), now.addingTimeInterval(86400)))
        }
        return now.addingTimeInterval(900)
    }
}
