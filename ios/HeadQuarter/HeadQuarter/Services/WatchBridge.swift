import Foundation
import WatchConnectivity
@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    private weak var store: AppStore?
    init(store: AppStore) {
        self.store = store; super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func publish() {
        guard let store, !store.isDemo, WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let payload = WatchPayload(dashboard: SharedStorage.load(), tasks: store.projects.flatMap { project in project.tasks.filter { $0.status != .completed }.map { .init(id: $0.id, project: project.name, title: $0.title, status: $0.status) } },
            incidents: store.projects.flatMap { project in project.activeIncidents.map { .init(id: $0.id, projectID: project.id, project: project.name, title: $0.title, health: $0.health, state: $0.state) } })
        do { try WCSession.default.updateApplicationContext(["workspace": try payload.boundedData()]) }
        catch { /* The next app update retries; lack of Watch delivery never changes service health. */ }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { Task { @MainActor in self.publish() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["action"] as? String == "acknowledge", let p = userInfo["projectID"] as? String, let i = userInfo["incidentID"] as? String,
              let projectID = UUID(uuidString: p), let incidentID = UUID(uuidString: i) else { return }
        Task { @MainActor in
            guard let store = self.store, let project = store.projects.first(where: { $0.id == projectID }), let incident = project.incidents.first(where: { $0.id == incidentID }) else { return }
            _ = store.commit { incident.transition(to: .acknowledged) }; self.publish()
        }
    }
}
