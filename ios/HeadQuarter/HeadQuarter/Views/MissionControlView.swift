import SwiftUI
import SwiftData

struct MissionOverviewView: View {
    @Environment(AppStore.self) private var store
    var operations: OperationsStore
    private let theme = MissionTheme(name: "hq")

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("HEADQUARTERS").font(.caption.weight(.semibold)).tracking(2.5).foregroundStyle(.cyan.opacity(0.8))
                            Text("Mission control").font(.title.bold())
                        }
                        Spacer()
                        SystemArtwork(system: operations.systems.first(where: { $0.id == "hq" }) ?? fallbackSystem, size: 56)
                    }
                    GlassPanel(theme: theme, padding: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.dotted.circle").font(.title).foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Coverage incomplete").font(.headline)
                                Text("App availability and agent execution remain unverified until reported.").font(.caption).foregroundStyle(theme.secondary)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        metric("Systems", value: "\(operations.systems.count)", detail: "Registered systems", symbol: "square.stack.3d.up")
                        metric("Tracked work", value: "\(store.projects.flatMap(\.tasks).filter { $0.status.isActive }.count)", detail: "Active workspace tasks", symbol: "play.circle")
                        metric("Open incidents", value: "\(store.projects.flatMap(\.activeIncidents).count)", detail: "Monitoring incidents", symbol: "exclamationmark.bubble")
                        metric("Public feed checks", value: "\(operations.cache.observations.keys.filter { $0.hasSuffix("-observer") }.count) / 3", detail: "Access & freshness", symbol: "waveform.path.ecg")
                    }
                    Button { store.selectedTab = 1 } label: {
                        HStack { Text("Explore your systems").font(.headline); Spacer(); Image(systemName: "arrow.right") }
                            .padding(14).background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.cyan.opacity(0.4)))
                    }.buttonStyle(.plain)
                    HStack { Text("Latest activity").font(.headline); Spacer(); Button("See all") { store.selectedTab = 3 }.font(.caption) }
                    let events = operations.events(for: nil, store: store)
                    if let event = events.first {
                        GlassPanel(theme: theme) { MissionActivityRow(event: event, theme: theme, maxLines: 1) }
                    } else {
                        Text("No activity has been reported. Refresh the available checks or configure a monitor.")
                            .font(.subheadline).foregroundStyle(theme.secondary)
                    }
                    if let error = operations.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Text("Foreground checks only · agent execution unverified.")
                        .font(.caption2).foregroundStyle(theme.secondary)
                }.padding(16)
            }.background(MissionBackground(theme: theme))
        }
        .foregroundStyle(theme.ink)
        .toolbar {
            Button { Task { await operations.refresh(store: store) } } label: {
                if operations.refreshing { ProgressView() } else { Label("Refresh checks", systemImage: "arrow.clockwise") }
            }.disabled(operations.refreshing || store.isDemo)
        }
        .refreshable { await operations.refresh(store: store) }
        .toolbarBackground(theme.background, for: .navigationBar, .tabBar)
        .preferredColorScheme(.dark)
    }
    private var fallbackSystem: SystemDefinition {
        .init(id: "hq", name: "Headquarters", aliases: [], asset: "BrandHeadquarters", theme: "hq", summary: "", repository: "", nodes: [], edges: [])
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        GlassPanel(theme: theme, padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Image(systemName: symbol).foregroundStyle(.cyan); Spacer(); Text(value).font(.title2.bold().monospacedDigit()) }
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SystemsView: View {
    @Environment(AppStore.self) private var store
    var operations: OperationsStore
    @State private var showingMap = false
    private let theme = MissionTheme(name: "hq")
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(spacing: 9) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Headquarters").font(.system(.largeTitle, design: .default).bold())
                            Text("Systems").font(.title3).foregroundStyle(theme.secondary)
                        }
                        Spacer(minLength: 4)
                        if let hq = operations.systems.first(where: { $0.id == "hq" }) { SystemArtwork(system: hq, size: 78) }
                    }.padding(.bottom, 12)
                    ForEach(operations.systems) { system in
                        NavigationLink {
                            OperationsDashboard(system: system, operations: operations)
                        } label: {
                            GlassPanel(theme: theme, padding: 11) {
                                HStack(spacing: 12) {
                                    SystemArtwork(system: system, size: 53)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(system.name).font(.headline).foregroundStyle(theme.ink)
                                        Text(system.summary).font(.caption2).foregroundStyle(theme.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        ConnectionBadge(state: operations.state(for: system, store: store, now: timeline.date))
                                        Text("HQ evidence").font(.system(size: 8)).foregroundStyle(theme.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        .accessibilityIdentifier("system-" + system.id)
                    }
                    GlassPanel(theme: theme, padding: 10) {
                        HStack(spacing: 12) {
                            Label("Verified", systemImage: "checkmark.circle.fill").foregroundStyle(ConnectionState.healthy.color)
                            Label("Fault", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                            Label("Missing HQ link", systemImage: "link.badge.plus").foregroundStyle(.gray)
                        }.font(.system(size: 9, weight: .medium)).frame(maxWidth: .infinity)
                    }.padding(.top, 7)
                    Text("A missing HQ report does not establish whether the owning app is online.").font(.caption2).foregroundStyle(theme.secondary)
                }.padding(.horizontal, 16).padding(.bottom, 18).padding(.top, 8)
            }.background(MissionBackground(theme: theme))
        }.foregroundStyle(theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showingMap = true } label: { Label("Ecosystem map", systemImage: "point.3.connected.trianglepath.dotted") } }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Manage", destination: ProjectsView()).font(.caption)
            }
        }
        .sheet(isPresented: $showingMap) { EcosystemMapScreen(operations: operations) }
        .toolbarBackground(theme.background, for: .navigationBar, .tabBar)
        .preferredColorScheme(.dark)
    }
}

struct OperationsDashboard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let system: SystemDefinition
    var operations: OperationsStore
    @State private var section = "Overview"
    @State private var selection: GraphSelection?
    @State private var expanded = false
    @State private var domain: FlowDomain = .runtime

    private var theme: MissionTheme { MissionTheme(name: system.theme) }
    private var project: Project? { operations.project(for: system, store: store) }
    private var monitoredCount: Int {
        system.edges.filter { operations.observation(for: $0.id, system: system, store: store) != nil }.count
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        SystemArtwork(system: system, size: 66)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(system.name).font(.system(.largeTitle).bold()).minimumScaleFactor(0.75).lineLimit(1)
                            Text("Operations").font(.title3).foregroundStyle(theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 4)
                    GlassPanel(theme: theme, padding: 12) {
                        HStack(alignment: .top) {
                            summary("HQ evidence") { ConnectionBadge(state: operations.state(for: system, store: store, now: timeline.date)) }
                            Divider()
                            summary("Observed") { Text("\(monitoredCount) / \(system.edges.count)").font(.headline.monospacedDigit()) }
                            Divider()
                            summary("Missing") {
                                Text("\(system.edges.filter { operations.state(for: $0, system: system, store: store, now: timeline.date) == .missing }.count)")
                                    .font(.headline.monospacedDigit())
                            }
                            Divider()
                            summary("Last check") {
                                if let date = lastCheck {
                                    Text(date, style: .time).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                } else { Text("Never").font(.caption) }
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    Picker("Operations section", selection: $section) {
                        ForEach(["Overview", "Map", "Activity", "Issues", "Config"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    if section == "Overview" || section == "Map" {
                        GlassPanel(theme: theme, padding: 9) {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("System interactions").font(.headline)
                                    Spacer()
                                    Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                                        .accessibilityLabel("Expand full system map")
                                }.padding(.horizontal, 5)
                                Picker("Flow domain", selection: $domain) {
                                    Text("Runtime & data").tag(FlowDomain.runtime)
                                    Text("Development").tag(FlowDomain.development)
                                }.pickerStyle(.segmented)
                                OperationsMapView(operations: operations, system: system, expanded: section == "Map",
                                                  domain: domain) { selection = $0 }
                                Text("Tap a node or connection to inspect its evidence and owner.")
                                    .font(.caption2).foregroundStyle(theme.secondary)
                            }
                        }
                        if section == "Map" { connectionList(now: timeline.date) }
                    }
                    if section == "Overview" || section == "Activity" {
                        HStack {
                            Text("Recent activity").font(.headline); Spacer()
                            if section == "Overview" { Button("See all") { section = "Activity" }.font(.caption) }
                        }
                        activity
                    }
                    if section == "Issues" { issues(now: timeline.date) }
                    if section == "Config" { configuration }
                    if let error = operations.error { Text(error).font(.caption).foregroundStyle(theme.isDark ? .orange : .red) }
                }.padding(16)
            }.background(MissionBackground(theme: theme))
        }
        .foregroundStyle(theme.ink).tint(theme.accent)
        .navigationTitle("Headquarters").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { Task { await operations.refresh(system: system, store: store) } } label: {
                if operations.refreshing { ProgressView() } else { Label("Recheck evidence", systemImage: "arrow.clockwise") }
            }.disabled(operations.refreshing || store.isDemo)
        }
        .sheet(item: $selection) { item in OperationsInspector(system: system, selection: item, operations: operations) }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    OperationsMapView(operations: operations, system: system, expanded: true, domain: domain) { selection = $0 }
                        .frame(width: 760).padding(22)
                }.background(MissionBackground(theme: theme))
                .navigationTitle(system.name + " map")
                .toolbar { Button("Done") { expanded = false } }
                .sheet(item: $selection) { item in OperationsInspector(system: system, selection: item, operations: operations) }
            }.preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .toolbarBackground(theme.background, for: .navigationBar, .tabBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar, .tabBar)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
        .accessibilityIdentifier("operations-" + system.id)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .tint(theme.accent)
    }

    private var lastCheck: Date? {
        (system.nodes.map(\.id) + system.edges.map(\.id))
            .compactMap { operations.observation(for: $0, system: system, store: store)?.checkedAt }.max()
    }
    private func summary<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9)).foregroundStyle(theme.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activity: some View {
        let events = operations.events(for: system, store: store)
        return GlassPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 13) {
                if events.isEmpty {
                    Text("No activity reported").font(.subheadline.weight(.semibold))
                    Text("Connect a monitor or health-only event source to populate this timeline.").font(.caption).foregroundStyle(theme.secondary)
                }
                ForEach(Array(events.prefix(section == "Overview" ? 3 : 100))) { event in
                    Button {
                        if let edge = system.edges.first(where: { $0.id == event.targetID }) {
                            selection = .init(id: edge.id, isEdge: true)
                        } else if let node = system.nodes.first(where: { $0.id == event.targetID }) {
                            selection = .init(id: node.id, isEdge: false)
                        } else if let edge = system.edges.first(where: { operations.service(for: $0.id, system: system, store: store)?.id.uuidString == event.targetID }) {
                            selection = .init(id: edge.id, isEdge: true)
                        } else { section = "Config" }
                    } label: { MissionActivityRow(event: event, theme: theme) }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func connectionList(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections & responsibility").font(.headline)
            ForEach(system.edges.filter { $0.domain == domain }) { edge in
                Button { selection = .init(id: edge.id, isEdge: true) } label: {
                    GlassPanel(theme: theme, padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edge.operation + " · " + edge.owner).font(.subheadline.weight(.semibold))
                                Text(title(edge.from) + " → " + title(edge.to)).font(.caption).foregroundStyle(theme.secondary)
                            }
                            Spacer()
                            ConnectionBadge(state: operations.state(for: edge, system: system, store: store, now: now))
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
    private func title(_ id: String) -> String { system.nodes.first { $0.id == id }?.title ?? id }

    private func issues(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup gaps & operational issues").font(.headline)
            Text("Missing means HQ has no configured evidence link. The owning app’s permissions and runtime remain unverified.")
                .font(.caption).foregroundStyle(theme.secondary)
            ForEach(system.nodes.filter {
                let state = operations.state(for: $0, system: system, store: store, now: now)
                return state != .healthy && state != .disabled
            }) { node in
                Button { selection = .init(id: node.id, isEdge: false) } label: {
                    GlassPanel(theme: theme) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(node.title).font(.headline); Spacer(); ConnectionBadge(state: operations.state(for: node, system: system, store: store, now: now)) }
                            Text(node.setup).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var configuration: some View {
        GlassPanel(theme: theme) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monitoring configuration").font(.headline)
                Text("Expected flows come from inspected source code. Direct telemetry is configured independently for each node or connection.")
                    .font(.caption).foregroundStyle(theme.secondary)
                if let project {
                    NavigationLink { ProjectDetailView(project: project) } label: { Label("Workspace tasks, services & settings", systemImage: "slider.horizontal.3") }
                    Button("Connect repository checks") { connectRepository(project) }
                        .disabled(operations.refreshing || store.isDemo)
                    Text("Repository evidence is development-only. Private repositories may require a read-only token in the existing service editor.")
                        .font(.caption2).foregroundStyle(theme.secondary)
                } else {
                    Text("No existing workspace is linked to this system. Create one only if you want to manage tasks and service monitors here.")
                        .font(.caption)
                    Button("Create workspace for " + system.name) {
                        _ = store.addProject(name: system.name, summary: system.summary, icon: "square.stack.3d.up")
                    }.disabled(store.isDemo)
                }
                Link("Inspect repository", destination: URL(string: "https://github.com/" + system.repository)!)
                Text("HQ checks public Crew and YKF publications while open. Calendar, health, bank, inventory and private agent data stay in their owning apps.")
                    .font(.caption).foregroundStyle(theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func connectRepository(_ project: Project) {
        let existing = project.services.first { $0.provider == "github" && $0.endpoint == system.repository }
        let service = existing ?? MonitoredService(name: "GitHub development", provider: "github", endpoint: system.repository, expiry: 604800)
        if existing == nil {
            service.critical = false
            guard store.commit({ project.services.append(service) }) else { return }
        }
        operations.bind(service, to: system.id + ".github-build")
        Task { await operations.refresh(system: system, store: store) }
    }
}

struct MissionActivityRow: View {
    let event: OperationActivity
    let theme: MissionTheme
    var maxLines = 3
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.state.symbol).foregroundStyle(event.state.color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.message).font(.caption.weight(.semibold)).lineLimit(maxLines).foregroundStyle(theme.ink)
                Text(event.actor).font(.caption2).foregroundStyle(theme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(event.timestamp, format: .dateTime.month().day().hour().minute()).font(.system(size: 9)).foregroundStyle(theme.secondary)
        }
    }
}

struct EcosystemMapScreen: View {
    @Environment(\.dismiss) private var dismiss
    var operations: OperationsStore
    @State private var selected = "briefing"
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("System", selection: $selected) {
                    ForEach(operations.systems) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                if let system = operations.systems.first(where: { $0.id == selected }) {
                    OperationsDashboard(system: system, operations: operations).id(selected)
                }
            }.toolbar { Button("Done") { dismiss() } }
        }
    }
}
