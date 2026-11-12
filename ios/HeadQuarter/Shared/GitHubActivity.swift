import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct RepositoryActivity: Codable, Sendable {
    struct Commit: Codable, Identifiable, Sendable {
        var id: String; var message: String; var author: String; var date: Date; var url: URL
    }
    struct PullRequest: Codable, Identifiable, Sendable {
        var id: Int; var title: String; var state: String; var draft: Bool; var updatedAt: Date; var url: URL
    }
    var repository: String
    var fetchedAt: Date
    var commits: [Commit]
    var pullRequests: [PullRequest]
    var workflow: Evidence
}
struct GitHubRepositoryProvider: Sendable {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }()
    func fetch(repository: String, token: String?) async throws -> RepositoryActivity {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && String($0).rangeOfCharacter(from: allowed.inverted) == nil }) else { throw MonitoringError.invalidURL }
        async let commits = request(path: "repos/\(repository)/commits?per_page=30", token: token)
        async let pulls = request(path: "repos/\(repository)/pulls?state=all&sort=updated&direction=desc&per_page=30", token: token)
        async let runs = request(path: "repos/\(repository)/actions/runs?per_page=1", token: token)
        return try await Self.decode(repository: repository, commits: commits, pulls: pulls, runs: runs, now: .now)
    }
    private func request(path: String, token: String?) async throws -> Data {
        guard let url = URL(string: "https://api.github.com/\(path)") else { throw MonitoringError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("HeadQuarter", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitoringError.badResponse }
        if http.statusCode == 401 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") != "0" && http.value(forHTTPHeaderField: "Retry-After") == nil) { throw MonitoringError.authentication }
        if http.statusCode == 403 || http.statusCode == 429 { throw MonitoringError.rateLimited(until: RateLimitPolicy.retryDate(headers: http.allHeaderFields, now: .now)) }
        guard http.statusCode == 200, data.count <= 4 * 1024 * 1024 else { throw MonitoringError.badResponse }
        return data
    }
    static func decode(repository: String, commits: Data, pulls: Data, runs: Data, now: Date) throws -> RepositoryActivity {
        struct CommitDTO: Decodable {
            struct Detail: Decodable {
                struct Author: Decodable { var name: String; var date: Date }
                var message: String; var author: Author
            }
            var sha: String; var html_url: URL; var commit: Detail
        }
        struct PullDTO: Decodable { var number: Int; var title: String; var state: String; var draft: Bool?; var merged_at: Date?; var updated_at: Date; var html_url: URL }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let commitItems = try decoder.decode([CommitDTO].self, from: commits)
        let pullItems = try decoder.decode([PullDTO].self, from: pulls)
        guard (commitItems.map(\.html_url) + pullItems.map(\.html_url)).allSatisfy({ $0.scheme == "https" && $0.host == "github.com" }) else { throw MonitoringError.invalidPayload }
        return .init(repository: repository, fetchedAt: now,
            commits: commitItems.map { .init(id: $0.sha, message: $0.commit.message, author: $0.commit.author.name, date: $0.commit.author.date, url: $0.html_url) },
            pullRequests: pullItems.map { .init(id: $0.number, title: $0.title, state: $0.merged_at == nil ? $0.state : "merged", draft: $0.draft ?? false, updatedAt: $0.updated_at, url: $0.html_url) },
            workflow: try GitHubActionsProvider.decodeEvidence(runs))
    }
}
