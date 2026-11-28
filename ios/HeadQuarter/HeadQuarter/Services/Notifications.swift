import Foundation
import UserNotifications

struct AlertPreferences: Codable {
    var enabled = false
    var threshold = 2
    var quietEnabled = false
    var quietStart = 22
    var quietEnd = 7
    var recovery = true
    var builds = true
    var milestones = true
    func isQuiet(at date: Date) -> Bool {
        guard quietEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietStart == quietEnd { return true }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
    }
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "alerts.preferences"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
    func save() throws { UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "alerts.preferences") }
}
actor AlertService {
    static let shared = AlertService()
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
    func send(id: String, title: String, message: String, severity: Int, category: String = "incident", projectID: UUID, incidentID: UUID? = nil) async throws -> Bool {
        let preferences = AlertPreferences.load()
        guard preferences.enabled, !preferences.isQuiet(at: .now), severity >= preferences.threshold else { return false }
        if category == "recovery" && !preferences.recovery { return false }
        if category == "build" && !preferences.builds { return false }
        if category == "milestone" && !preferences.milestones { return false }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = message; content.sound = .default
        content.userInfo = ["projectID": projectID.uuidString]
        if let incidentID { content.categoryIdentifier = "HQ_INCIDENT"; content.userInfo["incidentID"] = incidentID.uuidString }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
        return true
    }
}
