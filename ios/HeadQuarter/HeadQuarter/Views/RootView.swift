import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pendingRoute") private var pendingRoute = ""
    @AppStorage("foregroundCheckMinutes") private var checkMinutes = 5
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            NavigationStack { OverviewView() }.tabItem { Label("Overview", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack(path: $store.projectPath) {
                ProjectsView().navigationDestination(for: UUID.self) { id in
                    if let project = store.projects.first(where: { $0.id == id }) { ProjectDetailView(project: project) }
                    else { ContentUnavailableView("Project unavailable", systemImage: "folder.badge.questionmark") }
                }
            }.tabItem { Label("Projects", systemImage: "square.stack.3d.up") }.tag(1)
            NavigationStack { TasksView() }.tabItem { Label("Tasks", systemImage: "checklist") }.tag(2)
            NavigationStack { ActivityView() }.tabItem { Label("Activity", systemImage: "waveform.path.ecg") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(.indigo)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.isDemo { Text("DEMONSTRATION · Separate, temporary data").font(.caption.bold()).frame(maxWidth: .infinity).padding(8).background(.yellow.opacity(0.25)) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { WorkspaceErrorBanner() }
        .task {
            store.publishSnapshot()
            consumeIntentRoute()
            await store.operations.expire()
        }
        .task(id: checkMinutes) {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(1, checkMinutes) * 60)) } catch { return }
                if scenePhase == .active { await store.refresh() }
            }
        }
        .onChange(of: pendingRoute) { _, _ in consumeIntentRoute() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeIntentRoute(); store.publishSnapshot(); Task { await store.operations.expire() } }
        }
    }
    private func consumeIntentRoute() {
        guard !store.isDemo, !pendingRoute.isEmpty, let url = URL(string: pendingRoute) else { return }
        pendingRoute = ""; store.route(url)
    }
}

extension Health {
    var color: Color {
        switch self { case .healthy: return .green; case .needsHelp: return .yellow; case .error: return .orange; case .down: return .red; case .unknown: return .secondary }
    }
}
struct HealthBadge: View {
    var health: Health
    var body: some View {
        Label { Text(health.label).foregroundStyle(.primary) } icon: { Image(systemName: health.symbol).foregroundStyle(health.color) }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6).background(health.color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Operational health: \(health.label)")
    }
}
struct ProjectCard: View {
    var project: Project
    var now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: project.icon).font(.title2).foregroundStyle(.indigo).frame(width: 44, height: 44).background(.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) { Text(project.name).font(.headline); Text(project.phase).font(.subheadline).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption.bold())
            }
            HStack { Text("Development").font(.caption).foregroundStyle(.secondary); Spacer(); Text(project.progress, format: .percent.precision(.fractionLength(0))).font(.subheadline.monospacedDigit().bold()) }
            ProgressView(value: project.progress).tint(.indigo)
            HealthBadge(health: project.health(at: now).state)
            Text(project.health(at: now).explanation).font(.caption).foregroundStyle(.secondary)
            if let task = project.tasks.first(where: { $0.status.isActive }) { Label(task.title, systemImage: "play.circle").font(.subheadline).lineLimit(2) }
            VStack(alignment: .leading, spacing: 4) {
                let successfulEvents = project.events.filter { [.taskCompleted, .buildSucceeded, .deploymentCompleted, .serviceRecovered].contains($0.kind) }.map(\.timestamp)
                let successfulChecks = project.services.compactMap { service in service.evidence.flatMap { $0.state == .healthy ? $0.observedAt : nil } }
                if let success = (successfulEvents + successfulChecks).max() { Text("Last success: \(success.formatted(date: .abbreviated, time: .shortened))") }
                else { Text("Last success: no recorded activity") }
                if let update = project.services.compactMap(\.lastCheckedAt).max() { Text("Monitoring: \(update.formatted(date: .abbreviated, time: .shortened))") }
                else { Text("Monitoring: no check recorded") }
                Text("\(project.activeIncidents.count) open incidents · \(project.tasks.filter { $0.status == .blocked }.count) blocked tasks")
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}
struct MetricTile: View {
    var title: String; var value: String; var symbol: String; var color: Color = .indigo
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WorkspaceErrorBanner: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Dismiss error")
            }.padding().background(.regularMaterial).accessibilityElement(children: .contain)
        }
    }
}
