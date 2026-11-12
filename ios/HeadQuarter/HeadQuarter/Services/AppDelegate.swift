import UIKit
import UserNotifications

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var store: AppStore?
    private var pending: (String, UUID, UUID?)?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let acknowledge = UNNotificationAction(identifier: "HQ_ACKNOWLEDGE", title: "Acknowledge", options: [.authenticationRequired])
        let resolve = UNNotificationAction(identifier: "HQ_RESOLVE", title: "Resolve", options: [.authenticationRequired])
        center.setNotificationCategories([UNNotificationCategory(identifier: "HQ_INCIDENT", actions: [acknowledge, resolve], intentIdentifiers: [])])
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { Task { await RemotePushService.shared.received(token: deviceToken) } }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { RemotePushService.shared.status = "Apple registration failed: \(error.localizedDescription)" }
    func configure(_ store: AppStore) {
        self.store = store
        if let pending { handle(action: pending.0, projectID: pending.1, incidentID: pending.2); self.pending = nil }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list, .sound] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["projectID"] as? String, let projectID = UUID(uuidString: value) else { return }
        let incidentID = (response.notification.request.content.userInfo["incidentID"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        await MainActor.run { self.handle(action: action, projectID: projectID, incidentID: incidentID) }
    }
    private func handle(action: String, projectID: UUID, incidentID: UUID?) {
        guard let store else { pending = (action, projectID, incidentID); return }
        if action == UNNotificationDismissActionIdentifier { return }
        if let project = store.projects.first(where: { $0.id == projectID }), let incidentID,
           let incident = project.incidents.first(where: { $0.id == incidentID }) {
            if action == "HQ_ACKNOWLEDGE" { _ = store.commit { incident.transition(to: .acknowledged) } }
            if action == "HQ_RESOLVE" {
                _ = store.commit {
                    incident.transition(to: .resolved)
                    project.events.append(ActivityEvent(kind: .manualReport, message: "Incident resolved from notification: \(incident.title)", source: "User"))
                }
            }
        }
        store.selectedTab = 1; store.projectPath = [projectID]
        if let project = store.projects.first(where: { $0.id == projectID }) { Task { await store.refresh(project: project) } }
    }
}
