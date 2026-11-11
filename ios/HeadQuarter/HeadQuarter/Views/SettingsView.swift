import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ActivityKit
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("foregroundCheckMinutes") private var frequency = 5
    @State private var alerts = AlertPreferences.load()
    @State private var exportDocument = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingImport: WorkspaceBackup?
    @State private var confirmImport = false
    @State private var showingDemo = false
    @State private var status = ""
    var body: some View {
        Form {
            Section("Workspace") {
                NavigationLink("Dashboard card order") { DashboardOrderView() }
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Stepper("Check every \(frequency) min while open", value: $frequency, in: 1...60)
                Text("Automatic checks run only while this app is active. Configure service evidence expiry and request timeout in each service's settings.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Enable alerts", isOn: $alerts.enabled)
                Picker("Minimum severity", selection: $alerts.threshold) { Text("Needs Help and above").tag(2); Text("Errors and outages").tag(3); Text("Critical outages").tag(4) }
                Toggle("Service recovery", isOn: $alerts.recovery)
                Toggle("Failed builds", isOn: $alerts.builds)
                Toggle("Completed milestones", isOn: $alerts.milestones)
                Toggle("Quiet hours", isOn: $alerts.quietEnabled)
                if alerts.quietEnabled {
                    Picker("Start (local time)", selection: $alerts.quietStart) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    Picker("End (local time)", selection: $alerts.quietEnd) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                }
                Button("Save notification preferences") {
                    Task {
                        do {
                            if alerts.enabled, !store.isDemo {
                                let allowed = try await AlertService.shared.requestAuthorization()
                                guard allowed else { store.errorMessage = "Notification permission is disabled. Enable it in iPhone Settings."; return }
                            }
                            guard !store.isDemo else { status = "Demo preferences are not saved."; return }
                            try alerts.save(); status = "Notification preferences saved."
                        } catch { store.errorMessage = error.localizedDescription }
                    }
                }
                Text("Repeated reports update the existing incident; acknowledged incidents stay quiet. Quiet-hour alerts are suppressed, not queued. Outages cannot be detected while the app is suspended without an external monitor.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Backup and migration") {
                Button("Export workspace backup", systemImage: "square.and.arrow.up") {
                    do { exportDocument = BackupDocument(data: try BackupService.export(store.projects)); exporting = true }
                    catch { store.errorMessage = error.localizedDescription }
                }
                Button("Import native or Project HQ web backup", systemImage: "square.and.arrow.down") { importing = true }
                Text("Imports add projects and preserve existing data. The web app's JSON export is supported. Previous manual percentages are retained in import history; native completion uses task weights. Credentials are never exported.").font(.caption).foregroundStyle(.secondary)
            }.disabled(store.isDemo)
            Section("Connections and capabilities") {
                Text("Configure manual reports, HTTPS health endpoints, GitHub Actions, and an optional monitoring relay from a project's Connected Services section.")
                Text("Codex sessions: no supported live connection configured. No external account is connected automatically.").font(.caption).foregroundStyle(.secondary)
                Text("Cloud sync: local storage only. CloudKit synchronization is not enabled in this version; use backups to transfer your workspace.").font(.caption).foregroundStyle(.secondary)
                Text("Apple Watch companion: not included; this environment cannot build or validate watchOS targets.").font(.caption).foregroundStyle(.secondary)
                Button("End current Live Activities") { Task { await store.operations.endAll(); status = "Live Activities ended." } }.disabled(store.isDemo)
            }
            if !store.isDemo { Section("Demonstration") { Button("Explore temporary example data") { showingDemo = true }; Text("Example data lives in a separate in-memory workspace and never replaces your projects or widget snapshot.").font(.caption).foregroundStyle(.secondary) } }
            if !status.isEmpty { Section { Text(status).font(.subheadline).foregroundStyle(.secondary) } }
            Section { Text("HEAD QUARTER").font(.caption.weight(.semibold)).tracking(2); Text("A clear view of work and operations.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "head-quarter-backup") { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= BackupCodec.maximumBytes else { throw BackupError.invalid("File exceeds the 20 MB limit") }
                pendingImport = try BackupCodec.decode(Data(contentsOf: url, options: .mappedIfSafe)); confirmImport = true
            } catch { store.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Add \(pendingImport?.projects.count ?? 0) imported projects? Existing projects will be preserved. Imported connections require their tokens to be entered again.", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Import projects") { if let pendingImport, BackupService.restore(pendingImport, store: store) { status = "Imported \(pendingImport.projects.count) projects." }; pendingImport = nil }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        }
        .fullScreenCover(isPresented: $showingDemo) { DemoHost() }
    }
}
struct DashboardOrderView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Project.order) private var projects: [Project]
    var body: some View {
        List { ForEach(projects) { project in Label(project.name, systemImage: project.icon) }.onMove { indices, destination in
            var updated = projects; updated.move(fromOffsets: indices, toOffset: destination)
            _ = store.commit { for (index, project) in updated.enumerated() { project.order = index } }
        } }.environment(\.editMode, .constant(.active)).navigationTitle("Dashboard order")
    }
}
struct DemoHost: View {
    @Environment(\.dismiss) private var dismiss
    @State private var demo: AppStore?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Temporary demonstration").font(.headline); Spacer(); Button("Exit demo") { dismiss() } }.padding()
            if let demo { RootView().environment(demo).modelContainer(demo.container) }
            else if let error { ContentUnavailableView("Demo unavailable", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView().task { do { demo = try AppStore.demonstration() } catch { self.error = error.localizedDescription } } }
        }
    }
}
