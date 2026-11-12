import SwiftUI
import UniformTypeIdentifiers
struct MonitoringSetupView: View {
    @Environment(AppStore.self) private var store
    @State private var exporting = false
    @State private var document = BackupDocument()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
        List {
            Section {
                Text("Connect each project to evidence you control: an HTTPS health endpoint, GitHub repository, or authenticated relay/Codex observer. Unconfigured projects stay unknown. Repository activity never substitutes for an application's uptime check.").font(.subheadline)
                Button("Export configured relay checks") { export() }.disabled(store.isDemo)
                Text("Exports only configured IDs, endpoints, criteria and timing. Existing credentials remain in Keychain; private relay environment-variable names identify where you must configure the corresponding server credentials.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.projects) { project in
                Section(project.name) {
                    if project.services.isEmpty { Text("No live check configured").foregroundStyle(.secondary) }
                    ForEach(project.services) { service in VStack(alignment: .leading, spacing: 5) {
                        Text(service.name).font(.headline)
                        Text("\(service.provider) · expires after \(Int(service.expiry)) seconds").font(.caption)
                        HealthBadge(health: HealthEngine.evaluate(service.reading, now: timeline.date).state)
                        Text(service.id.uuidString).font(.caption2.monospaced()).textSelection(.enabled)
                    } }
                    Button("Open project connections") { store.selectedTab = 1; store.projectPath = [project.id] }
                }
            }
        }
        }.navigationTitle("Ecosystem connections")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "head-quarter-relay-config") { result in if case .failure(let error) = result { store.errorMessage = error.localizedDescription } }
    }
    private func export() {
        do {
            var rows: [[String: Any]] = []
            for project in store.projects {
                for service in project.services where service.provider != "manual" {
                    var row: [String: Any] = ["projectID": project.id.uuidString, "serviceID": service.id.uuidString, "name": service.name, "critical": service.critical, "evidenceExpirySeconds": Int(service.expiry)]
                    if service.provider == "https" {
                        row["endpoint"] = service.endpoint; row["timeoutSeconds"] = Int(service.timeout)
                        row["intervalSeconds"] = max(60, min(Int(service.expiry) / 2, 300))
                        row["expectedHTTPStatus"] = service.expectedHTTPStatus; row["requiredBodyText"] = service.requiredBodyText; row["timestampPath"] = service.timestampPath
                        if try CredentialVault.read(service.id) != nil { row["tokenEnv"] = "HQ_TARGET_TOKEN_" + service.id.uuidString.replacingOccurrences(of: "-", with: "") }
                    }
                    rows.append(row)
                }
            }
            document = BackupDocument(data: try JSONSerialization.data(withJSONObject: ["version": 1, "services": rows], options: [.prettyPrinted, .sortedKeys])); exporting = true
        } catch { store.errorMessage = error.localizedDescription }
    }
}
