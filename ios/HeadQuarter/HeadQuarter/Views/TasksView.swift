import SwiftUI
import SwiftData
struct TaskSelection: Identifiable { var project: Project; var task: WorkItem?; var id: UUID { task?.id ?? project.id } }
struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var selection: TaskSelection?
    @State private var board = true
    @State private var search = ""
    private func items(_ status: WorkStatus? = nil) -> [TaskSelection] {
        projects.flatMap { project in project.tasks.filter { task in
            (status == nil || task.status == status) && (!store.showOnlyActive || task.status.isActive) && (search.isEmpty || task.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.priority > $1.priority }.map { TaskSelection(project: project, task: $0) } }
    }
    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            if store.showOnlyActive { HStack { Text("Active tasks"); Spacer(); Button("Show all") { store.showOnlyActive = false } }.font(.subheadline).padding() }
            Picker("Layout", selection: $board) { Text("Kanban").tag(true); Text("List").tag(false) }.pickerStyle(.segmented).padding()
            if projects.isEmpty { ContentUnavailableView("No projects yet", systemImage: "checklist", description: Text("Create a project before adding tasks.")) }
            else if board {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(WorkStatus.allCases) { status in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(status.rawValue).font(.headline); Spacer(); Text("\(items(status).count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                ScrollView {
                                    LazyVStack(spacing: 10) {
                                        ForEach(items(status)) { item in
                                            if let task = item.task {
                                                Button { selection = item } label: {
                                                    VStack(alignment: .leading, spacing: 8) { Text(item.project.name).font(.caption).foregroundStyle(.indigo); WorkRow(task: task) }
                                                        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 14))
                                                }.buttonStyle(.plain).draggable(task.id.uuidString)
                                            }
                                        }
                                        if items(status).isEmpty { Text("No tasks").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90) }
                                    }
                                }
                            }.padding(14).frame(width: 285).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first.flatMap(UUID.init(uuidString:)), let item = items().first(where: { $0.task?.id == id }), let task = item.task else { return false }
                                    return store.saveTask(task, in: item.project, isNew: false, title: task.title, notes: task.notes, status: status, priority: task.priority, weight: task.weight, assignee: task.assignee, blocker: task.blocker, due: task.plannedAt, parentID: task.parentID, dependencyIDs: task.dependencyIDs, milestoneID: task.milestoneID)
                                }
                        }
                    }.padding(.horizontal).padding(.bottom)
                }
            } else {
                List {
                    if items().isEmpty { ContentUnavailableView("No matching tasks", systemImage: "checklist") }
                    ForEach(items()) { item in
                        if let task = item.task { Button { selection = item } label: { VStack(alignment: .leading) { Text(item.project.name).font(.caption).foregroundStyle(.indigo); WorkRow(task: task) } }.buttonStyle(.plain) }
                    }
                }
            }
        }
        .navigationTitle("Tasks").searchable(text: $search)
        .toolbar { Menu { ForEach(projects) { project in Button(project.name) { selection = .init(project: project) } } } label: { Label("Create task", systemImage: "plus") }.disabled(projects.isEmpty) }
        .sheet(item: $selection) { TaskEditor(project: $0.project, existing: $0.task) }
    }
}
struct TaskEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var project: Project
    var existing: WorkItem? = nil
    @State private var title = ""
    @State private var notes = ""
    @State private var status = WorkStatus.backlog
    @State private var priority = 2
    @State private var weight = 1.0
    @State private var assignee = ""
    @State private var blocker = ""
    @State private var hasDate = false
    @State private var due = Date.now
    @State private var parentID: UUID?
    @State private var milestoneID: UUID?
    @State private var dependencies: Set<UUID> = []
    @State private var deleting = false
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section("\(project.name) · Task") {
                    TextField("Title", text: $title)
                    TextField("Details", text: $notes, axis: .vertical)
                    Picker("Status", selection: $status) { ForEach(WorkStatus.allCases) { Text($0.rawValue).tag($0) } }
                    Stepper("Priority: \(priority)", value: $priority, in: 1...5)
                    HStack { Text("Work weight"); Spacer(); TextField("Weight", value: $weight, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    TextField("Developer or AI agent", text: $assignee)
                    TextField("Blocker / required action", text: $blocker, axis: .vertical)
                }
                Section("Schedule") {
                    Toggle("Planned completion", isOn: $hasDate)
                    if hasDate { DatePicker("Due", selection: $due, displayedComponents: .date) }
                    if let actual = existing?.completedAt { Text("Actual completion: \(actual.formatted())").foregroundStyle(.secondary) }
                }
                Section("Structure") {
                    Picker("Parent task", selection: $parentID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(project.tasks.filter { $0.id != existing?.id }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("Milestone", selection: $milestoneID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(project.milestones) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Section { ForEach(project.tasks.filter { $0.id != existing?.id }) { task in
                    Toggle(task.title, isOn: Binding(get: { dependencies.contains(task.id) }, set: { if $0 { dependencies.insert(task.id) } else { dependencies.remove(task.id) } }))
                } } header: { Text("Depends on") } footer: { Text("Dependencies must be completed before starting or completing this task. Each task contributes its configured weight to project progress, including subtasks.") }
                if let existing, existing.status.isActive {
                    Section("Live Activity") {
                        Button("Start Live Activity", systemImage: "livephoto") { store.operations.start(project: project, task: existing) }.disabled(store.isDemo)
                        Text("Tracks this operation for up to one hour. Complete the task or end the activity from Settings when finished.").font(.caption).foregroundStyle(.secondary)
                        if let message = store.operations.message { Text(message).font(.caption).foregroundStyle(.orange) }
                    }
                }
                if existing != nil {
                    Section { Button("Delete task", role: .destructive) { deleting = true } }
                }
            }
            .safeAreaInset(edge: .bottom) { WorkspaceErrorBanner() }
            .navigationTitle(existing == nil ? "New task" : "Edit task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !weight.isFinite || weight <= 0) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let task = existing {
                    title = task.title; notes = task.notes; status = task.status; priority = task.priority; weight = task.weight
                    assignee = task.assignee; blocker = task.blocker; hasDate = task.plannedAt != nil; due = task.plannedAt ?? .now
                    parentID = task.parentID; milestoneID = task.milestoneID; dependencies = Set(task.dependencyIDs)
                }
            }
            .confirmationDialog("Delete this task? Dependent tasks will have this dependency removed.", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { if let existing { if store.deleteTask(existing, in: project) { dismiss() } } } }
        }
    }
    private func save() {
        let task = existing ?? WorkItem(title: title)
        if store.saveTask(task, in: project, isNew: existing == nil, title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, status: status, priority: priority, weight: weight, assignee: assignee, blocker: blocker, due: hasDate ? due : nil, parentID: parentID, dependencyIDs: Array(dependencies), milestoneID: milestoneID) { dismiss() }
    }
}
