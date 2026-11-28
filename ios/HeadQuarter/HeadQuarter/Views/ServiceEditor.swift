import SwiftUI
struct ServiceEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var project: Project
    var existing: MonitoredService? = nil
    @State private var name = ""
    @State private var provider = "manual"
    @State private var endpoint = ""
    @State private var token = ""
    @State private var removeToken = false
    @State private var hasToken = false
    @State private var critical = true
    @State private var expectedHTTPStatus = 200
    @State private var requiredBodyText = ""
    @State private var timestampPath = ""
    @State private var expiry = 60.0
    @State private var timeout = 15.0
    @State private var reportState = Health.unknown
    @State private var explanation = ""
    @State private var source = "Manual report"
    @State private var includeReport = false
    @State private var eventKind = EventKind.manualReport
    @State private var deleting = false
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Service name", text: $name)
                    Picker("Provider", selection: $provider) {
                        Text("Manual evidence").tag("manual")
                        Text("HTTPS health endpoint").tag("https")
                        Text("GitHub Actions").tag("github")
                        Text("Monitoring relay").tag("relay")
                    }.disabled(store.isDemo)
                    if provider != "manual" {
                        TextField(provider == "github" ? "owner/repository" : "https://…", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !store.isDemo {
                            SecureField(hasToken ? "Replace stored bearer token" : "Bearer token (optional for public services)", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                            if hasToken { Toggle("Remove stored token", isOn: $removeToken) }
                        }
                    }
                    if provider == "https" {
                        Stepper("Expected HTTP status: \(expectedHTTPStatus)", value: $expectedHTTPStatus, in: 200...299)
                        TextField("Required response text (optional)", text: $requiredBodyText).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if provider == "https" { TextField("JSON timestamp path for data feeds (optional)", text: $timestampPath).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    Toggle("Critical service", isOn: $critical)
                    Stepper("Evidence expires after \(Int(expiry)) minutes", value: $expiry, in: 1...10080, step: 1)
                    Stepper("Request timeout: \(Int(timeout)) seconds", value: $timeout, in: 5...60, step: 5)
                }
                if provider == "github" { Section { Text("Checks the latest workflow run, not your app's availability. Evidence is dated to that run; old successful builds become unknown when they expire.").font(.caption).foregroundStyle(.secondary) } }
                if provider == "relay" { Section { Text("Enter the HTTPS /v1/projects/{projectID}/services/{serviceID}/evidence URL supplied by your monitoring relay and its read token. No relay is connected automatically.").font(.caption).foregroundStyle(.secondary) } }
                if provider == "relay", let existing {
                    Section("Relay identifiers") {
                        LabeledContent("Project") { Text(project.id.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                        LabeledContent("Service") { Text(existing.id.uuidString).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                if let existing {
                    Section("Latest evidence") {
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        VStack(alignment: .leading, spacing: 8) {
                        let health = HealthEngine.evaluate(existing.reading, now: timeline.date)
                        HealthBadge(health: health.state)
                        Text(health.explanation).font(.subheadline)
                        if let at = health.observedAt { Text("Observed: \(at.formatted())").font(.caption) }
                        if let checked = existing.lastCheckedAt { Text("Last check: \(checked.formatted())").font(.caption) }
                        if let next = existing.nextAllowedCheckAt, next > timeline.date { Text("Rate limited until \(next.formatted())").font(.caption).foregroundStyle(.orange) }
                        }
                        }
                    }
                }
                Section {
                    Toggle("Record a manual report on save", isOn: $includeReport)
                    if includeReport {
                        Picker("Event", selection: $eventKind) { ForEach(EventKind.allCases) { Text($0.label).tag($0) } }
                        Picker("Observed health", selection: $reportState) { ForEach(Health.allCases) { Text($0.label).tag($0) } }
                        TextField("Explanation and supporting evidence", text: $explanation, axis: .vertical)
                        TextField("Evidence source", text: $source)
                    }
                } header: { Text("Manual evidence") } footer: { Text("Reports are timestamped now and expire using the configured threshold. Record only evidence you actually observed. Tokens stay in this device's Keychain and are excluded from exports.") }
                if existing != nil { Section { Button("Remove service", role: .destructive) { deleting = true } } }
            }
            .safeAreaInset(edge: .bottom) { WorkspaceErrorBanner() }
            .navigationTitle(existing == nil ? "Add service" : "Edit service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (includeReport && (explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let service = existing {
                    name = service.name; provider = service.provider; endpoint = service.endpoint; critical = service.critical; expiry = service.expiry / 60; timeout = service.timeout; expectedHTTPStatus = service.expectedHTTPStatus; requiredBodyText = service.requiredBodyText; timestampPath = service.timestampPath
                    if !store.isDemo { do { hasToken = try CredentialVault.read(service.id) != nil } catch { store.errorMessage = error.localizedDescription } }
                }
            }
            .confirmationDialog("Remove this service and its credential? Its activity and incident history will remain.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard let service = existing else { return }
                    if store.removeService(service, in: project) { dismiss() }
                }
            }
        }
    }
    private func save() {
        if provider != "manual" {
            if provider == "github" {
                let parts = endpoint.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { store.errorMessage = "Use owner/repository for GitHub Actions."; return }
            } else {
                guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { store.errorMessage = "Use an HTTPS URL without embedded credentials."; return }
            }
        }
        let service = existing ?? MonitoredService(name: name)
        let serviceID = service.id
        do {
            let oldToken = store.isDemo ? nil : try CredentialVault.read(service.id)
            if oldToken != nil, token.isEmpty, !removeToken, provider != "manual", let existing {
                let oldURL = URL(string: existing.endpoint), newURL = URL(string: endpoint)
                let sameOrigin = existing.provider == provider && (provider == "github" || (oldURL?.scheme == newURL?.scheme && oldURL?.host == newURL?.host && oldURL?.port == newURL?.port))
                guard sameOrigin else { throw WorkspaceSyncError.configuration("Re-enter or remove the token when changing a service's provider or host.") }
            }
            if !store.isDemo {
                if provider == "manual" { try CredentialVault.set("", for: serviceID) }
                else if removeToken || !token.isEmpty { try CredentialVault.set(removeToken ? "" : token, for: serviceID) }
            }
            let saved = store.commit {
                // A changed connection must not inherit a passing result from the previous endpoint.
                if service.provider != provider || service.endpoint != endpoint || service.expectedHTTPStatus != expectedHTTPStatus || service.requiredBodyText != requiredBodyText || service.timestampPath != timestampPath { service.evidence = nil; service.lastCheckedAt = nil; service.nextAllowedCheckAt = nil }
                service.configurationRevision += 1
                service.expectedHTTPStatus = expectedHTTPStatus; service.requiredBodyText = requiredBodyText; service.timestampPath = timestampPath
                service.name = name; service.provider = provider; service.endpoint = endpoint
                service.critical = critical; service.expiry = expiry * 60; service.timeout = timeout
                if existing == nil { project.services.append(service) }
            }
            guard saved else {
                if !store.isDemo { try CredentialVault.set(oldToken ?? "", for: serviceID) }; return
            }
            if includeReport { store.record(Evidence(state: reportState, explanation: explanation, observedAt: .now, source: store.isDemo ? "DEMO · \(source)" : source), for: service, in: project, kind: eventKind) }
            dismiss()
        } catch { store.errorMessage = error.localizedDescription }
    }
}
