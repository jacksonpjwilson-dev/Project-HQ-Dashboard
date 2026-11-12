import SwiftUI
struct ProjectDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var project: Project
    @State private var editing = false
    @State private var addingTask = false
    @State private var addingService = false
    @State private var selectedTask: WorkItem?
    @State private var selectedService: MonitoredService?
    @State private var deleting = false
    @State private var milestoneName = ""
    @State private var milestoneDue = Date.now
    @State private var milestoneHasDate = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            List {
                Section {
                    ProjectCard(project: project, now: timeline.date).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    if !project.summary.isEmpty { Text(project.summary).foregroundStyle(.secondary) }
                }
                Section("Milestones") {
                    ForEach(project.milestones.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }) { milestone in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(milestone.title, systemImage: milestone.completedAt != nil ? "checkmark.seal.fill" : "flag")
                            if let due = milestone.dueAt { Text("Planned: \(due.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                            if let completed = milestone.completedAt { Text("Completed: \(completed.formatted())").font(.caption).foregroundStyle(.green) }
                        }.swipeActions { Button("Delete", role: .destructive) {
                            _ = store.commit { for task in project.tasks where task.milestoneID == milestone.id { task.milestoneID = nil }; project.milestones.removeAll { $0.id == milestone.id }; store.context.delete(milestone) }
                        } }
                    }
                    TextField("New milestone", text: $milestoneName)
                    Toggle("Planned completion date", isOn: $milestoneHasDate)
                    if milestoneHasDate { DatePicker("Due", selection: $milestoneDue, displayedComponents: .date) }
                    Button("Add milestone") {
                        if store.commit({ let m = Milestone(title: milestoneName.trimmingCharacters(in: .whitespacesAndNewlines)); m.dueAt = milestoneHasDate ? milestoneDue : nil; project.milestones.append(m) }) { milestoneName = "" }
                    }.disabled(milestoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Active tasks") {
                    taskRows(project.tasks.filter { $0.status.isActive })
                    Button("Create task", systemImage: "plus") { addingTask = true }
                }
                Section("Blocked / required actions") {
                    taskRows(project.tasks.filter { $0.status == .blocked || $0.status == .failed })
                    ForEach(project.activeIncidents) { incident in IncidentRow(incident: incident, project: project) }
                }
                Section("All tracked work") { taskRows(project.tasks.sorted { $0.priority > $1.priority }) }
                Section {
                    ForEach(project.services) { service in
                        Button { selectedService = service } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(service.name).font(.headline); Spacer(); Text(service.provider.uppercased()).font(.caption2).foregroundStyle(.secondary) }
                                let health = HealthEngine.evaluate(service.reading, now: timeline.date)
                                HealthBadge(health: health.state)
                                Text(health.explanation).font(.caption).foregroundStyle(.secondary)
                                if let at = health.observedAt { Text(at, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }.buttonStyle(.plain)
                    }
                    Button("Add service or manual monitor", systemImage: "plus") { addingService = true }
                    Button { Task { await store.refresh(project: project) } } label: {
                        HStack { Text("Check connected services"); Spacer(); if store.isRefreshing { ProgressView() } }
                    }.disabled(store.isRefreshing || store.isDemo)
                } header: { Text("Connected services") } footer: { Text("Checks run while the app is open. Freshness rules continue to apply when checks stop; continuous monitoring requires an external relay.") }
                Section("Repository activity") {
                    ForEach(project.services.filter { $0.provider == "github" }) { service in NavigationLink(service.endpoint.isEmpty ? "Configure repository" : service.endpoint) { RepositoryActivityView(project: project, service: service) } }
                    if !project.services.contains(where: { $0.provider == "github" }) { Text("Add a GitHub service to fetch commits, pull requests, and workflow status.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Build and deployment history") {
                    eventRows(project.events.filter { [.buildSucceeded, .buildFailed, .deploymentCompleted].contains($0.kind) })
                }
                Section("Error history") {
                    eventRows(project.events.filter { [.taskFailed, .buildFailed, .healthCheckFailed, .integrationDisconnected].contains($0.kind) })
                }
                Section("Activity timeline") { eventRows(project.events) }
            }
        }
        .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { Menu {
            Button("Edit project", systemImage: "pencil") { editing = true }
            Button("Delete project", systemImage: "trash", role: .destructive) { deleting = true }
        } label: { Label("Project actions", systemImage: "ellipsis.circle") } }
        .sheet(isPresented: $editing) { ProjectEditor(project: project) }
        .sheet(isPresented: $addingTask) { TaskEditor(project: project) }
        .sheet(item: $selectedTask) { TaskEditor(project: project, existing: $0) }
        .sheet(isPresented: $addingService) { ServiceEditor(project: project) }
        .sheet(item: $selectedService) { ServiceEditor(project: project, existing: $0) }
        .confirmationDialog("Delete \(project.name) and its tasks, monitoring history, and incidents?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) { if store.removeProject(project) { dismiss() } }
        }
        .alert("Live Activity", isPresented: Binding(get: { store.operations.message != nil }, set: { if !$0 { store.operations.message = nil } })) {
            Button("OK") { store.operations.message = nil }
        } message: { Text(store.operations.message ?? "") }
    }
    @ViewBuilder private func taskRows(_ tasks: [WorkItem]) -> some View {
        if tasks.isEmpty { Text("No tasks in this section").foregroundStyle(.secondary).font(.subheadline) }
        ForEach(tasks) { task in
            Button { selectedTask = task } label: { WorkRow(task: task) }.buttonStyle(.plain)
                .contextMenu {
                    if task.status.isActive { Button("Start one-hour Live Activity", systemImage: "livephoto") { store.operations.start(project: project, task: task) }.disabled(store.isDemo) }
                }
        }
    }
    @ViewBuilder private func eventRows(_ events: [ActivityEvent]) -> some View {
        if events.isEmpty { Text("No recorded events").foregroundStyle(.secondary).font(.subheadline) }
        ForEach(events.sorted { $0.timestamp > $1.timestamp }.prefix(50)) { EventRow(event: $0) }
    }
}
struct WorkRow: View {
    var task: WorkItem
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Image(systemName: task.status == .completed ? "checkmark.circle.fill" : task.status == .blocked ? "hand.raised" : "circle").foregroundStyle(task.status == .completed ? .green : .secondary); Text(task.title).font(.headline) }
            HStack { Text(task.status.rawValue); Text("P\(task.priority)"); if !task.assignee.isEmpty { Text(task.assignee) }; Spacer(); Text("Weight \(task.weight.formatted())") }.font(.caption).foregroundStyle(.secondary)
            if !task.blocker.isEmpty { Text(task.blocker).font(.caption).foregroundStyle(.orange) }
            if let due = task.plannedAt { Text("Due \(due.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 3)
    }
}
struct IncidentRow: View {
    @Environment(AppStore.self) private var store
    var incident: Incident
    var project: Project
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthBadge(health: incident.health)
            Text(incident.title).font(.subheadline)
            Text("\(incident.state.rawValue.capitalized) · \(incident.updatedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            if incident.state != .resolved {
                HStack {
                    if incident.state == .open { Button("Acknowledge") { _ = store.commit { incident.transition(to: .acknowledged) } } }
                    Button("Resolve") {
                        _ = store.commit {
                            incident.transition(to: .resolved)
                            project.events.append(ActivityEvent(kind: .manualReport, message: "Incident resolved manually: \(incident.title). Service health still follows evidence.", source: "User"))
                        }
                    }
                }.font(.caption).buttonStyle(.bordered)
            }
        }.padding(.vertical, 4)
    }
}
struct EventRow: View {
    var event: ActivityEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.kind.label).font(.subheadline.bold())
            Text(event.message).font(.subheadline)
            Text("\(event.source) · \(event.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
