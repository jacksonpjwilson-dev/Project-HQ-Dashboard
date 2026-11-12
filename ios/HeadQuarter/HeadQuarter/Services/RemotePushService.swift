import Foundation
import UIKit
import Observation
@MainActor @Observable final class RemotePushService {
    static let shared = RemotePushService()
    var status = "Remote alerts are not registered"
    private let credentialID = UUID(uuidString: "341AABED-3186-4B7D-843D-6D902E177919")!
    private let tokenID = UUID(uuidString: "2D25F3D9-3E06-4133-9674-599F8A166A5D")!
    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "push.deviceID") { return id }
        let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "push.deviceID"); return id
    }
    func register(endpoint: String, credential: String) async {
        do {
            guard Bundle.main.object(forInfoDictionaryKey: "HQPushEnabled") as? Bool == true else { throw WorkspaceSyncError.configuration("Enable the Push Notifications capability with your Apple team, aps-environment entitlement, and HQPushEnabled before registering. No APNs connection has been claimed.") }
            guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw MonitoringError.invalidURL }
            if !credential.isEmpty { try CredentialVault.set(credential, for: credentialID); UserDefaults.standard.set(endpoint, forKey: "push.credentialEndpoint") }
            guard try CredentialVault.read(credentialID) != nil, UserDefaults.standard.string(forKey: "push.credentialEndpoint") == endpoint else { throw WorkspaceSyncError.configuration("Enter the relay's device-registration token.") }
            UserDefaults.standard.set(endpoint, forKey: "push.endpoint")
            guard try await AlertService.shared.requestAuthorization() else { throw WorkspaceSyncError.configuration("Allow notifications in iPhone Settings before registering.") }
            var prefs = AlertPreferences.load(); prefs.enabled = true; try prefs.save()
            status = "Waiting for Apple's device token…"
            UIApplication.shared.registerForRemoteNotifications()
        } catch { status = error.localizedDescription }
    }
    func received(token: Data) async {
        do { try CredentialVault.set(token.map { String(format: "%02x", $0) }.joined(), for: tokenID); try await upload() }
        catch { status = "Device token received; relay registration failed: \(error.localizedDescription)" }
    }
    func refreshPreferences() async { do { if try CredentialVault.read(tokenID) != nil { try await upload() } } catch { status = error.localizedDescription } }
    private func upload() async throws {
        guard let token = try CredentialVault.read(tokenID) else { return }
        let prefs = AlertPreferences.load(), encoder = JSONEncoder()
        let preferences = try JSONSerialization.jsonObject(with: encoder.encode(prefs))
        let environment = Bundle.main.object(forInfoDictionaryKey: "HQAPNSEnvironment") as? String ?? "development"
        let body = try JSONSerialization.data(withJSONObject: ["id": deviceID, "token": token, "environment": environment, "bundleID": Bundle.main.bundleIdentifier ?? "", "timezone": TimeZone.current.identifier, "preferences": preferences])
        _ = try await request(method: "POST", suffix: "/v1/devices", body: body)
        status = "Registered with the relay. APNs delivery still requires a signed-device test."
    }
    func revoke() async {
        UIApplication.shared.unregisterForRemoteNotifications()
        do {
            _ = try await request(method: "DELETE", suffix: "/v1/devices/\(deviceID)", body: nil)
            try CredentialVault.set("", for: tokenID); status = "Device registration removed"
        } catch { status = "Disabled locally; server removal is pending: \(error.localizedDescription)" }
    }
    private func request(method: String, suffix: String, body: Data?) async throws -> Data {
        guard let base = UserDefaults.standard.string(forKey: "push.endpoint"), let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + suffix), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, UserDefaults.standard.string(forKey: "push.credentialEndpoint") == base,
              let credential = try CredentialVault.read(credentialID) else { throw WorkspaceSyncError.configuration("Configure the HTTPS relay base URL and its device-registration token.") }
        var request = URLRequest(url: url, timeoutInterval: 30); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw WorkspaceSyncError.configuration("The relay rejected device registration. Check its device token, APNs configuration, topic, and environment.") }
        return data
    }
}
