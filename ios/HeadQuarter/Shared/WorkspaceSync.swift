import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct RemoteWorkspace: Codable, Sendable {
    var version: Int = 1
    var revision: Int
    var backup: WorkspaceBackup?
}
enum WorkspaceSyncError: LocalizedError {
    case conflict([String]), remoteChanged, invalidResponse, configuration(String), localChanged
    var errorDescription: String? {
        switch self {
        case .conflict(let paths): return "Both devices changed the same information: \(paths.prefix(5).joined(separator: ", ")). Your local data has been preserved. Review before choosing a side."
        case .remoteChanged: return "The remote workspace changed during synchronization. Retry to merge the latest edits."
        case .invalidResponse: return "The synchronization server returned an invalid response."
        case .configuration(let detail): return detail
        case .localChanged: return "Local edits arrived during synchronization. They are preserved; sync again before applying remote changes."
        }
    }
}
protocol WorkspaceTransport: Sendable {
    func fetch() async throws -> RemoteWorkspace
    func save(_ backup: WorkspaceBackup, expectedRevision: Int) async throws -> RemoteWorkspace
}
// Field-level three-way merge. Collections keyed by id merge independent edits and deletions.
// Concurrent edits to the same field, or delete/edit races, are surfaced rather than overwritten.
enum WorkspaceMerge {
    static func merge(base: WorkspaceBackup?, local: WorkspaceBackup, remote: WorkspaceBackup?) throws -> WorkspaceBackup {
        try local.validate(); try remote?.validate(); try base?.validate()
        guard let remote else { return local }
        func projects(_ value: WorkspaceBackup?) throws -> Any? {
            guard let value else { return nil }
            let object = try JSONSerialization.jsonObject(with: BackupCodec.encode(value)) as! [String: Any]
            return canonical(object["projects"] ?? [])
        }
        let result = try mergeValue(base: projects(base) ?? [], local: projects(local), remote: projects(remote), path: "projects")
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "exportedAt": ISO8601DateFormatter().string(from: .now), "projects": result ?? []], options: [.sortedKeys])
        return try BackupCodec.decode(data)
    }
    static func equivalent(_ lhs: WorkspaceBackup, _ rhs: WorkspaceBackup) throws -> Bool {
        func payload(_ value: WorkspaceBackup) throws -> NSObject {
            let object = try JSONSerialization.jsonObject(with: BackupCodec.encode(value)) as! [String: Any]
            return canonical(object["projects"] ?? []) as! NSObject
        }
        return try payload(lhs).isEqual(payload(rhs))
    }
    private static func canonical(_ value: Any) -> Any {
        if let dict = value as? [String: Any] { return dict.mapValues { canonical($0) } }
        if let array = value as? [Any] {
            let items = array.map { canonical($0) }
            if items.allSatisfy({ ($0 as? [String: Any])?["id"] is String }) {
                return items.sorted { (($0 as! [String: Any])["id"] as! String) < (($1 as! [String: Any])["id"] as! String) }
            }
            return items
        }
        return value
    }
    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let lhs = lhs as? NSObject, let rhs = rhs as? NSObject else { return false }
        return lhs.isEqual(rhs)
    }
    private static func mergeValue(base: Any?, local: Any?, remote: Any?, path: String) throws -> Any? {
        if equal(local, remote) { return local }
        if equal(local, base) { return remote }
        if equal(remote, base) { return local }
        if let l = local as? [String: Any], let r = remote as? [String: Any], base == nil || base is [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var result: [String: Any] = [:]
            for key in Set(b.keys).union(l.keys).union(r.keys).sorted() {
                if let value = try mergeValue(base: b[key], local: l[key], remote: r[key], path: "\(path).\(key)") { result[key] = value }
            }
            return result
        }
        if let l = local as? [Any], let r = remote as? [Any], base == nil || base is [Any],
           (l + r + (base as? [Any] ?? [])).allSatisfy({ ($0 as? [String: Any])?["id"] is String }) {
            func indexed(_ array: [Any]) -> [String: Any] { Dictionary(array.map { (($0 as! [String: Any])["id"] as! String, $0) }, uniquingKeysWith: { first, _ in first }) }
            let li = indexed(l), ri = indexed(r), bi = indexed(base as? [Any] ?? [])
            return try Set(li.keys).union(ri.keys).union(bi.keys).sorted().compactMap { id in try mergeValue(base: bi[id], local: li[id], remote: ri[id], path: "\(path)[\(id)]") }
        }
        throw WorkspaceSyncError.conflict([path])
    }
}
struct HTTPWorkspaceTransport: WorkspaceTransport {
    var endpoint: URL
    var token: String
    func fetch() async throws -> RemoteWorkspace { try await request(method: "GET", backup: nil, revision: nil) }
    func save(_ backup: WorkspaceBackup, expectedRevision: Int) async throws -> RemoteWorkspace { try await request(method: "PUT", backup: backup, revision: expectedRevision) }
    private func request(method: String, backup: WorkspaceBackup?, revision: Int?) async throws -> RemoteWorkspace {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil, !token.isEmpty else { throw WorkspaceSyncError.configuration("Use an HTTPS workspace endpoint and a synchronization token stored in Keychain.") }
        var request = URLRequest(url: endpoint, timeoutInterval: 60); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let revision { request.setValue("\"\(revision)\"", forHTTPHeaderField: "If-Match") }
        if let backup { request.httpBody = try BackupCodec.encode(backup); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WorkspaceSyncError.invalidResponse }
        if http.statusCode == 409 || http.statusCode == 412 { throw WorkspaceSyncError.remoteChanged }
        if http.statusCode == 401 || http.statusCode == 403 { throw MonitoringError.authentication }
        if http.statusCode == 429 { throw MonitoringError.rateLimited(until: RateLimitPolicy.retryDate(headers: http.allHeaderFields, now: .now)) }
        guard http.statusCode == 200, data.count <= BackupCodec.maximumBytes + 4096 else { throw WorkspaceSyncError.invalidResponse }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(RemoteWorkspace.self, from: data)
        guard result.version == 1, result.revision >= 0 else { throw WorkspaceSyncError.invalidResponse }
        try result.backup?.validate(); return result
    }
}
