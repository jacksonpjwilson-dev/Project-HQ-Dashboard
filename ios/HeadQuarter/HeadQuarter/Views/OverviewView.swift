import SwiftUI
import SwiftData
struct OverviewView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Project.order) private var projects: [Project]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMAND CENTRE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        Text("Your work. In view.").font(.largeTitle.bold())
                        Text("Development progress and operational evidence, together.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    let readings = projects.flatMap(\.services).map { HealthEngine.evaluate($0.reading, now: timeline.date).state }
                    let tasks = projects.flatMap(\.tasks)
                    let progress = ProgressEngine.completion(tasks.map { .init(weight: $0.weight, completed: $0.status == .completed) })
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricTile(title: "Projects tracked", value: "\(projects.count)", symbol: "square.stack.3d.up")
                        MetricTile(title: "Development complete", value: progress.formatted(.percent.precision(.fractionLength(0))), symbol: "chart.bar.xaxis")
                        MetricTile(title: "Healthy services", value: "\(readings.filter { $0 == .healthy }.count)", symbol: Health.healthy.symbol, color: .green)
                        MetricTile(title: "Require attention", value: "\(readings.filter { $0 == .needsHelp }.count)", symbol: Health.needsHelp.symbol, color: .yellow)
                        MetricTile(title: "Service errors", value: "\(readings.filter { $0 == .error }.count)", symbol: Health.error.symbol, color: .orange)
                        MetricTile(title: "Critical services down", value: "\(readings.filter { $0 == .down }.count)", symbol: Health.down.symbol, color: .red)
                        MetricTile(title: "Active tasks", value: "\(tasks.filter { $0.status.isActive }.count)", symbol: "play.circle")
                        MetricTile(title: "Completed tasks", value: "\(tasks.filter { $0.status == .completed }.count)", symbol: "checkmark.circle")
                    }
                    Text("\(readings.filter { $0 == .unknown }.count) services have unknown health. Unconfigured projects remain unknown.").font(.caption).foregroundStyle(.secondary)
                    HStack { Text("Project status").font(.title2.bold()); Spacer(); if store.isRefreshing { ProgressView() } }
                    if projects.isEmpty {
                        ContentUnavailableView("Your command centre is ready", systemImage: "square.stack.3d.up", description: Text("Add a project in the Projects tab to get started."))
                    }
                    ForEach(projects) { project in
                        Button { store.selectedTab = 1; store.projectPath = [project.id] } label: { ProjectCard(project: project, now: timeline.date) }.buttonStyle(.plain)
                    }
                }.padding()
            }.background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Overview").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { Task { await store.refresh() } } label: { Label("Check services", systemImage: "arrow.clockwise") }.disabled(store.isRefreshing || store.isDemo) }
        .refreshable { await store.refresh() }
    }
}
struct ProjectsView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var search = ""
    @State private var sort = "Dashboard order"
    @State private var filter = "All"
    @State private var adding = false
    var filtered: [Project] {
        let result = projects.filter { project in
            let health = project.health().state
            return (search.isEmpty || project.name.localizedCaseInsensitiveContains(search)) &&
                (!store.showOnlyHelp || project.requiresAttention) &&
                (filter == "All" || health.label == filter)
        }
        switch sort {
        case "Priority": return result.sorted { $0.priority == $1.priority ? $0.order < $1.order : $0.priority > $1.priority }
        case "Completion": return result.sorted { $0.progress == $1.progress ? $0.order < $1.order : $0.progress < $1.progress }
        case "Health": return result.sorted { $0.health().state.severity > $1.health().state.severity }
        default: return result
        }
    }
    var body: some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(spacing: 14) {
                if store.showOnlyHelp { HStack { Text("Projects requiring help"); Spacer(); Button("Clear") { store.showOnlyHelp = false } }.font(.subheadline).padding() }
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(filtered) { project in NavigationLink(value: project.id) { ProjectCard(project: project, now: .now) }.buttonStyle(.plain) }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Projects").searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(["Dashboard order", "Priority", "Completion", "Health"], id: \.self) { Text($0) } }
                    Picker("Health", selection: $filter) { Text("All").tag("All"); ForEach(Health.allCases) { Text($0.label).tag($0.label) } }
                } label: { Label("Sort and filter", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Label("Add project", systemImage: "plus") } }
        }
        .sheet(isPresented: $adding) { ProjectEditor(project: nil) }
    }
}
struct ProjectEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var project: Project?
    @State private var name = ""
    @State private var summary = ""
    @State private var icon = "square.stack.3d.up"
    @State private var phase = "Planning"
    @State private var priority = 2
    @State private var requireAll = true
    @State private var loaded = false
    private let icons = ["square.stack.3d.up", "building.2", "airplane.arrival", "carrot", "creditcard", "figure.strengthtraining.traditional", "sun.horizon", "square.grid.2x2", "terminal", "gearshape.2"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Project") { TextField("Name", text: $name); TextField("Description", text: $summary, axis: .vertical)
                    Picker("Icon", selection: $icon) { ForEach(icons, id: \.self) { Label($0, systemImage: $0).tag($0) } }
                    Picker("Development phase", selection: $phase) { ForEach(["Planning", "Design", "Implementation", "Testing", "Release", "Maintenance"], id: \.self) { Text($0) } }
                    Stepper("Priority: \(priority)", value: $priority, in: 1...5)
                }
                Section { Toggle("Require all checks to pass", isOn: $requireAll) } footer: { Text("When enabled, missing or stale evidence prevents a green project status. Confirmed failures always take precedence.") }
            }.safeAreaInset(edge: .bottom) { WorkspaceErrorBanner() }.navigationTitle(project == nil ? "New project" : "Edit project")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let saved: Bool
                            if let project { saved = store.commit { project.name = name.trimmingCharacters(in: .whitespacesAndNewlines); project.summary = summary; project.icon = icon; project.phase = phase; project.priority = priority; project.requireAllChecks = requireAll } }
                            else {
                                saved = store.commit {
                                    let p = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), summary: summary, icon: icon, order: (store.projects.map(\.order).max() ?? -1) + 1)
                                    p.phase = phase; p.priority = priority; p.requireAllChecks = requireAll; store.context.insert(p)
                                }
                            }
                            if saved { dismiss() }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { guard !loaded else { return }; loaded = true; if let project { name = project.name; summary = project.summary; icon = project.icon; phase = project.phase; priority = project.priority; requireAll = project.requireAllChecks } }
        }
    }
}
