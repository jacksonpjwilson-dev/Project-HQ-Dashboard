import SwiftUI

struct OperationsInspector: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let system: SystemDefinition
    let selection: GraphSelection
    var operations: OperationsStore
    @State private var addingMonitor = false

    private var node: OperationNode? { system.nodes.first { $0.id == selection.id } }
    private var edge: OperationEdge? { system.edges.first { $0.id == selection.id } }
    private var theme: MissionTheme { .init(name: system.theme) }
    private var project: Project? { operations.project(for: system, store: store) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Form {
                    Section {
                        ConnectionBadge(state: currentState(timeline.date))
                        Text(selection.isEdge ? "Connection evidence" : "Node evidence").font(.caption).foregroundStyle(.secondary)
                        if let edge {
                            Text(title(edge.from) + " → " + title(edge.to)).font(.headline)
                            LabeledContent("Operation", value: edge.operation)
                            LabeledContent("Responsible actor", value: edge.owner)
                            Text(edge.impact)
                            if let upstream = operations.observation(for: edge.from, system: system, store: store),
                               upstream.currentState(at: timeline.date) == .failed {
                                Text("Upstream evidence reports a failure. Downstream work may be blocked; this is not a second independently observed failure.")
                                    .foregroundStyle(.orange)
                            }
                        }
                        if let node {
                            LabeledContent("Type", value: node.kind.capitalized)
                            LabeledContent("Owner", value: node.owner)
                            Text(node.purpose)
                            Text("Source inspected · " + node.source).font(.caption).textSelection(.enabled)
                            if let reason = node.disabledReason { Text(reason).foregroundStyle(.secondary) }
                        }
                    } header: { Text(node?.title ?? edge?.operation ?? "Evidence inspector") }

                    Section("Observed evidence") {
                        if let observation = operations.observation(for: selection.id, system: system, store: store) {
                            Text(observation.explanation(at: timeline.date))
                            LabeledContent("Source", value: observation.source)
                            LabeledContent("Observation time") { Text(observation.observedAt, format: .dateTime.month().day().hour().minute()) }
                            LabeledContent("Last attempt") { Text(observation.checkedAt, style: .relative) }
                            if let success = observation.lastSuccess { LabeledContent("Last success") { Text(success, format: .dateTime.month().day().hour().minute()) } }
                            if let failure = observation.lastFailure { LabeledContent("Last failure") { Text(failure, format: .dateTime.month().day().hour().minute()) } }
                            LabeledContent("Freshness window", value: "\(Int(observation.expiry)) seconds")
                            if let latency = observation.latencyMilliseconds { LabeledContent("Measured request time", value: "\(latency) ms") }
                        } else {
                            Text("No direct operational evidence has been received for this \(selection.isEdge ? "connection" : "node").")
                            Text("Missing describes HQ monitoring setup. It does not establish denied permission, missing credentials in another app, or an outage.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if operations.observation(for: selection.id, system: system, store: store) != nil ||
                            operations.service(for: selection.id, system: system, store: store) != nil {
                            Button("Recheck available evidence") {
                                Task { await operations.refresh(system: system, store: store) }
                            }.disabled(operations.refreshing || store.isDemo)
                        }
                    }

                    Section("Recommended action") {
                        if let node { Text(node.setup) }
                        if let edge {
                            Text(system.nodes.first(where: { $0.id == edge.from })?.setup ?? edge.impact)
                            Text("Bind a monitor only if its evidence measures this exact operation. Endpoint reachability alone does not establish successful downstream processing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if node?.disabledReason == nil {
                            Toggle("Pause this dashboard binding", isOn: Binding(
                                get: { operations.isPaused(selection.id) },
                                set: { operations.setPaused($0, target: selection.id) }
                            ))
                            Text("This excludes the binding from this dashboard’s refreshes. Existing workspace monitors remain independently configured; the owning app is unaffected.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let project, node?.disabledReason == nil {
                        Section("Evidence binding") {
                            Picker("Workspace monitor", selection: Binding(
                                get: { operations.service(for: selection.id, system: system, store: store)?.id.uuidString ?? "" },
                                set: { id in operations.bind(project.services.first { $0.id.uuidString == id }, to: selection.id) }
                            )) {
                                Text("No monitor bound").tag("")
                                ForEach(project.services) { service in Text(service.name).tag(service.id.uuidString) }
                            }
                            Button("Add a service monitor") { addingMonitor = true }
                            NavigationLink("Manage workspace services") { ProjectDetailView(project: project) }
                        }
                    }
                    if let node {
                        Section("Downstream impact") {
                            let ids = OperationsHealth.downstream(of: node.id, edges: system.edges)
                            if ids.isEmpty { Text("No downstream runtime nodes are declared.") }
                            ForEach(system.nodes.filter { ids.contains($0.id) }) { affected in
                                Text(affected.title + " · " + affected.owner)
                            }
                            if node.kind == "development" { Text("Development evidence is separate from runtime availability.") }
                        }
                    }
                    if system.id == "crew", ["crew.agents", "crew.roster"].contains(selection.id) {
                        Section("Declared agents · execution unverified") {
                            if let agents = operations.cache.agents, !agents.isEmpty {
                                ForEach(agents) { agent in
                                    NavigationLink {
                                        Form {
                                            LabeledContent("Declared role", value: agent.role.isEmpty ? "Not published" : agent.role)
                                            LabeledContent("Reports to", value: agent.reportsTo ?? "Not published")
                                            ConnectionBadge(state: .unknown)
                                            Text("This identity comes from the public Crew roster. No authorized execution, failure or task stream is connected.")
                                        }.navigationTitle(agent.name)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(agent.name)
                                            Text(agent.role.isEmpty ? "Role not published" : agent.role).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } else { Text("Refresh the public roster to inspect declared agents.") }
                        }
                    }
                    if node?.title == "GitHub" {
                        Section("Shared development dependency") {
                            Text("GitHub hosts these repositories. A provider incident can affect their development delivery; installed runtime remains independent.")
                            ForEach(operations.systems) { system in Text(system.name + " · " + system.repository).font(.caption) }
                        }
                    }
                    Section("Relevant activity") {
                        let events = operations.events(for: system, store: store).filter { $0.targetID == selection.id }
                        if events.isEmpty { Text("No recorded activity for this item.").foregroundStyle(.secondary) }
                        ForEach(Array(events.prefix(20))) { event in MissionActivityRow(event: event, theme: theme) }
                    }
                }.scrollContentBackground(.hidden)
                    .background(MissionBackground(theme: theme))
            }
            .navigationTitle(node?.title ?? edge?.operation ?? "Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $addingMonitor) {
                if let project { ServiceEditor(project: project) }
            }
        }.tint(theme.accent).preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func title(_ id: String) -> String { system.nodes.first { $0.id == id }?.title ?? id }
    private func currentState(_ date: Date) -> ConnectionState {
        if let node { return operations.state(for: node, system: system, store: store, now: date) }
        if let edge { return operations.state(for: edge, system: system, store: store, now: date) }
        return .unknown
    }
}

struct MissionHistoryView: View {
    @Environment(AppStore.self) private var store
    var operations: OperationsStore
    @State private var selectedSystem = "all"
    @State private var filter = "Activity"
    @State private var severity = "All"
    @State private var selection: GraphSelection?
    @State private var inspectedSystem: SystemDefinition?
    private let theme = MissionTheme(name: "hq")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Activity or alerts", selection: $filter) {
                    Text("Activity").tag("Activity")
                    Text("Alerts & setup").tag("Alerts")
                }.pickerStyle(.segmented)
                Picker("App", selection: $selectedSystem) {
                    Text("All systems").tag("all")
                    ForEach(operations.systems) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                if filter == "Activity" {
                    let spec = operations.systems.first { $0.id == selectedSystem }
                    Picker("Outcome", selection: $severity) {
                        Text("All outcomes").tag("All")
                        Text("Failures").tag("Failures")
                        Text("Unverified reports").tag("Unverified")
                    }.pickerStyle(.menu)
                    let events = operations.events(for: spec, store: store).filter {
                        severity == "All" || (severity == "Failures" && $0.state == .failed) || (severity == "Unverified" && $0.state == .unknown)
                    }
                    if events.isEmpty { Text("No recorded activity. Refresh public feeds or configure workspace monitors.").foregroundStyle(theme.secondary) }
                    ForEach(events) { event in
                        if let system = operations.systems.first(where: { $0.id == event.systemID }) {
                            if let target = graphTarget(event, in: system) {
                                Button {
                                    inspectedSystem = system; selection = target
                                } label: { GlassPanel(theme: theme) { MissionActivityRow(event: event, theme: theme) } }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink { OperationsDashboard(system: system, operations: operations) } label: {
                                    GlassPanel(theme: theme) { MissionActivityRow(event: event, theme: theme) }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    NavigationLink("Workspace activity & incident history") { ActivityView() }
                } else {
                    ForEach(operations.systems.filter { selectedSystem == "all" || $0.id == selectedSystem }) { system in
                        NavigationLink {
                            OperationsDashboard(system: system, operations: operations)
                        } label: {
                            GlassPanel(theme: theme) {
                                HStack {
                                    SystemArtwork(system: system, size: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(system.name).font(.headline)
                                        Text("Review reporting gaps, stale evidence and incidents").font(.caption).foregroundStyle(theme.secondary)
                                    }
                                    Spacer()
                                    ConnectionBadge(state: operations.state(for: system, store: store, now: .now))
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(16)
        }.background(MissionBackground(theme: theme)).foregroundStyle(theme.ink)
            .navigationTitle("Activity & alerts")
            .sheet(item: $selection) { item in
                if let inspectedSystem { OperationsInspector(system: inspectedSystem, selection: item, operations: operations) }
            }
            .preferredColorScheme(.dark)
    }
    private func graphTarget(_ event: OperationActivity, in system: SystemDefinition) -> GraphSelection? {
        if system.edges.contains(where: { $0.id == event.targetID }) { return .init(id: event.targetID, isEdge: true) }
        if system.nodes.contains(where: { $0.id == event.targetID }) { return .init(id: event.targetID, isEdge: false) }
        if let edge = system.edges.first(where: { operations.service(for: $0.id, system: system, store: store)?.id.uuidString == event.targetID }) {
            return .init(id: edge.id, isEdge: true)
        }
        return nil
    }

}
