import SwiftUI
struct RemotePushSettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("push.endpoint") private var endpoint = ""
    @State private var credential = ""
    var body: some View {
        Form {
            TextField("https://relay-host", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Save or replace device-registration token", text: $credential).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Register this iPhone for remote alerts") { Task { await RemotePushService.shared.register(endpoint: endpoint, credential: credential); credential = "" } }.disabled(store.isDemo)
            Button("Remove registration", role: .destructive) { Task { await RemotePushService.shared.revoke() } }.disabled(store.isDemo)
            Text(RemotePushService.shared.status).font(.caption).foregroundStyle(.secondary)
            Text("Requires Apple Push Notifications signing, a physical-device token, an HTTPS relay with HQ_DEVICE_TOKEN, and an APNs provider key stored only on the server. Sandbox and production environments must match your signed build. No provider key or relay secret is embedded in this app.").font(.caption)
            Text("Quiet hours, severity and category preferences are sent when you save notification preferences. Remote alert receipt opens the relevant project and requests current service evidence.").font(.caption)
        }.navigationTitle("Remote push alerts")
    }
}
