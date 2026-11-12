import SwiftUI
import Observation
import WatchConnectivity
@MainActor @Observable final class WatchStore: NSObject, WCSessionDelegate {
    var payload: WatchPayload?
    var message = "Open Head Quarter on your paired iPhone to send a snapshot."
    override init() {
        if let data = UserDefaults.standard.data(forKey: "watch.workspace") { payload = try? JSONDecoder().decode(WatchPayload.self, from: data) }
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = session.receivedApplicationContext["workspace"] as? Data { Task { @MainActor in self.receive(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["workspace"] as? Data else { return }; Task { @MainActor in self.receive(data) }
    }
    private func receive(_ data: Data) {
        guard data.count < 1024 * 1024, let snapshot = try? JSONDecoder().decode(WatchPayload.self, from: data) else { message = "The phone snapshot could not be read."; return }
        payload = snapshot; UserDefaults.standard.set(data, forKey: "watch.workspace"); message = "Received \(snapshot.dashboard.generatedAt.formatted(date: .omitted, time: .shortened))"
    }
    func acknowledge(_ incident: WatchPayload.Alert) {
        guard WCSession.default.activationState == .activated else { message = "Watch connection is not ready."; return }
        WCSession.default.transferUserInfo(["action": "acknowledge", "projectID": incident.projectID.uuidString, "incidentID": incident.id.uuidString])
        message = "Acknowledgement queued for iPhone. Status changes after the phone confirms it."
    }
}
@main struct HeadQuarterWatchApp: App {
    @State private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    List {
                        if let payload = store.payload {
                            Section("Projects") { ForEach(payload.dashboard.projects) { project in
                                VStack(alignment: .leading) { Text(project.name).font(.headline); Label(project.currentHealth(at: timeline.date).label, systemImage: project.currentHealth(at: timeline.date).symbol).font(.caption); ProgressView(value: project.progress) }
                            } }
                            Section("Incidents") { ForEach(payload.incidents) { incident in
                                VStack(alignment: .leading) {
                                    Text(incident.project).font(.caption); Text(incident.title)
                                    if incident.state == .open { Button("Acknowledge") { store.acknowledge(incident) } }
                                    else { Text(incident.state.rawValue.capitalized).font(.caption) }
                                }
                            } }
                            Section("Outstanding work") { ForEach(payload.tasks) { task in VStack(alignment: .leading) { Text(task.project).font(.caption); Text(task.title); Text(task.status.rawValue).font(.caption) } } }
                            Section { Text("\(payload.dashboard.overallProgress.formatted(.percent)) development complete").font(.caption) }
                        }
                        Text(store.message).font(.caption).foregroundStyle(.secondary)
                    }
                }.navigationTitle("Head Quarter")
            }
        }
    }
}
