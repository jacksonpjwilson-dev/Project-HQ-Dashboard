import SwiftUI
struct SyncSettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("sync.mode") private var mode = "relay"
    @AppStorage("sync.endpoint") private var endpoint = ""
    @AppStorage("sync.container") private var container = "iCloud.com.headquarter.app"
    @AppStorage("sync.auto") private var automatic = false
    @State private var token = ""
    @State private var resolution: String?
    @State private var preparing = false
    private let credentialID = UUID(uuidString: "C5A234A8-71A2-4C7B-92AD-6DF7AE8D9B31")!
    var body: some View {
        Form {
            Section("Backend") {
                Picker("Synchronize using", selection: $mode) { Text("Private relay").tag("relay"); Text("Private iCloud / CloudKit").tag("cloudkit") }
                if mode == "relay" {
                    TextField("https://host/v1/workspace", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Save or replace synchronization token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                } else { TextField("iCloud container identifier", text: $container).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if mode == "cloudkit" { Button("Authorize current iCloud account") { resolution = "authorizeCloud" } }
                Toggle("Synchronize while app is active", isOn: $automatic)
                Button("Merge and synchronize") { run("merge") }.disabled(store.sync.isSyncing || store.isDemo)
                if store.sync.isSyncing || preparing { ProgressView("Synchronizing…") }
                Text(store.sync.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Resolve a conflict explicitly") {
                Button("Use this device's workspace") { resolution = "device" }
                Button("Use remote workspace") { resolution = "remote" }
                Text("Normal sync merges independent field edits and deletions. Conflicting edits stop synchronization and preserve this device's data. Choosing a side keeps an automatic local safety backup before applying changes; credentials never leave Keychain.").font(.caption).foregroundStyle(.secondary)
            }.disabled(store.sync.isSyncing || store.isDemo)
            Section("Connection requirements") {
                Text("Relay sync requires a deployed HTTPS /v1/workspace endpoint and its separate HQ_SYNC_TOKEN. CloudKit requires your Apple signing team, a private iCloud container, entitlements, schema deployment, and HQCloudKitEnabled. No account is connected automatically.").font(.caption)
                Text("Sync is user-triggered and works between configured devices. Offline changes remain local until you sync. Independent starter projects keep their IDs and are not silently matched by name.").font(.caption)
            }
        }.disabled(store.sync.isSyncing || preparing || store.isDemo).navigationTitle("Project & task sync")
            .safeAreaInset(edge: .bottom) { WorkspaceErrorBanner() }
            .confirmationDialog(resolution == "authorizeCloud" ? "Authorize uploading this device's workspace to the current iCloud account? Review the signed-in account in iPhone Settings first." : "Replace the other side with the chosen workspace? A local safety copy is retained before changing this device.", isPresented: Binding(get: { resolution != nil }, set: { if !$0 { resolution = nil } }), titleVisibility: .visible) {
                Button("Confirm synchronization") { let chosen = resolution ?? "merge"; resolution = nil; run(chosen) }
                Button("Cancel", role: .cancel) { resolution = nil }
            }
    }
    private func run(_ resolution: String) {
        guard !preparing, !store.sync.isSyncing else { return }; preparing = true
        Task {
            defer { preparing = false }
            do {
                let transport: any WorkspaceTransport
                let scope: String
                if mode == "cloudkit" {
                    let cloud = CloudWorkspaceTransport(containerIdentifier: container)
                    scope = try await cloud.accountScope()
                    if resolution == "authorizeCloud" { UserDefaults.standard.set(scope, forKey: "sync.authorizedCloudScope"); store.sync.status = "Current iCloud account authorized. Tap Merge and synchronize to transfer workspace data."; return }
                    guard UserDefaults.standard.string(forKey: "sync.authorizedCloudScope") == scope else { throw WorkspaceSyncError.configuration("Authorize the current iCloud account before syncing. Account changes never trigger an automatic upload.") }
                    transport = cloud
                }
                else {
                    if !token.isEmpty { try CredentialVault.set(token, for: credentialID); UserDefaults.standard.set(endpoint, forKey: "sync.credentialEndpoint"); token = "" }
                    guard UserDefaults.standard.string(forKey: "sync.credentialEndpoint") == endpoint else { throw WorkspaceSyncError.configuration("Re-enter the synchronization token when changing the endpoint.") }
                    guard let url = URL(string: endpoint), let credential = try CredentialVault.read(credentialID) else { throw WorkspaceSyncError.configuration("Enter the relay endpoint and synchronization token.") }
                    transport = HTTPWorkspaceTransport(endpoint: url, token: credential); scope = endpoint
                }
                await store.sync.synchronize(store: store, transport: transport, scope: scope, resolution: resolution)
            } catch { store.errorMessage = error.localizedDescription }
        }
    }
}
