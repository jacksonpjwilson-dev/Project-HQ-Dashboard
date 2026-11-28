import ActivityKit
import Foundation
struct OperationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var progress: Double?
        var status: String
    }
    var taskID: UUID
    var projectID: UUID
    var projectName: String
    var startedAt: Date
    var deadline: Date
}
