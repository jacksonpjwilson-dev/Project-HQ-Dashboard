import SwiftUI
import SwiftData
struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \Project.order) private var projects: [Project]
    @State private var incidentsOnly = false
    @State private var showResolved = false
    var body: some View {
        @Bindable var store = store
        List {
            Section {
                Toggle("Incidents only", isOn: $incidentsOnly)
                Toggle("Errors only", isOn: $store.showOnlyErrors)
                if incidentsOnly { Toggle("Include resolved incidents", isOn: $showResolved) }
            }
            if incidentsOnly {
                ForEach(projects) { project in
                    let incidents = project.incidents.filter { (showResolved || $0.state != .resolved) && (!store.showOnlyErrors || $0.health == .error || $0.health == .down) }.sorted { $0.updatedAt > $1.updatedAt }
                    if !incidents.isEmpty { Section(project.name) { ForEach(incidents) { IncidentRow(incident: $0, project: project) } } }
                }
                if projects.flatMap(\.incidents).filter({ showResolved || $0.state != .resolved }).isEmpty { ContentUnavailableView("No incidents", systemImage: "checkmark.shield", description: Text("Health still depends on fresh monitoring evidence.")) }
            } else {
                let events = projects.flatMap { project in project.events.map { (project.name, $0) } }.filter { !store.showOnlyErrors || [.taskFailed, .buildFailed, .healthCheckFailed, .integrationDisconnected].contains($0.1.kind) }.sorted { $0.1.timestamp > $1.1.timestamp }
                if events.isEmpty { ContentUnavailableView("No recorded activity", systemImage: "waveform.path.ecg", description: Text("Task changes and monitoring reports appear here.")) }
                ForEach(events, id: \.1.id) { item in VStack(alignment: .leading, spacing: 4) { Text(item.0).font(.caption).foregroundStyle(.indigo); EventRow(event: item.1) } }
            }
        }.navigationTitle("Activity")
    }
}
