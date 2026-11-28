import Foundation
import ActivityKit
import Observation
@MainActor @Observable final class LiveOperations {
    var message: String?
    func start(project: Project, task: WorkItem) {
        message = nil
        let operationTitle = task.title
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = "Enable Live Activities in iPhone Settings."; return }
        guard task.status.isActive else { message = "Start a task before starting its Live Activity."; return }
        guard Activity<OperationAttributes>.activities.isEmpty else { message = "End the current operation before starting another."; return }
        let deadline = Date.now.addingTimeInterval(3600)
        do {
            let activity = try Activity.request(attributes: OperationAttributes(taskID: task.id, projectID: project.id, projectName: project.name, startedAt: .now, deadline: deadline),
                content: ActivityContent(state: OperationAttributes.ContentState(title: operationTitle, progress: nil, status: task.status.rawValue), staleDate: deadline), pushType: nil)
            Task {
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                await activity.end(ActivityContent(state: .init(title: operationTitle, progress: nil, status: "Time limit reached"), staleDate: .now), dismissalPolicy: .immediate)
            }
        } catch { message = error.localizedDescription }
    }
    func update(task: WorkItem) async {
        for activity in Activity<OperationAttributes>.activities where activity.attributes.taskID == task.id {
            let state = OperationAttributes.ContentState(title: task.title, progress: task.status == .completed ? 1 : nil, status: task.status.rawValue)
            let content = ActivityContent(state: state, staleDate: activity.attributes.deadline)
            if task.status == .completed || task.status == .failed || !task.status.isActive {
                await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
            } else { await activity.update(content) }
        }
    }
    func end(projectID: UUID, taskID: UUID? = nil) async {
        for activity in Activity<OperationAttributes>.activities where activity.attributes.projectID == projectID && (taskID == nil || activity.attributes.taskID == taskID) {
            await activity.end(ActivityContent(state: .init(title: activity.content.state.title, progress: nil, status: "Ended"), staleDate: .now), dismissalPolicy: .immediate)
        }
    }
    func endAll() async {
        for activity in Activity<OperationAttributes>.activities {
            await activity.end(ActivityContent(state: .init(title: activity.content.state.title, progress: nil, status: "Ended"), staleDate: .now), dismissalPolicy: .immediate)
        }
    }
    func expire() async {
        for activity in Activity<OperationAttributes>.activities where activity.attributes.deadline < .now {
            await activity.end(ActivityContent(state: .init(title: activity.content.state.title, progress: nil, status: "Time limit reached"), staleDate: .now), dismissalPolicy: .immediate)
        }
    }
}
