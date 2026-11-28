import AppIntents
import Foundation
import SwiftData

struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Head Quarter project"
    static var defaultQuery = ProjectEntityQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct ProjectEntityQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        let container = try Persistence.container()
        return try container.mainContext.fetch(FetchDescriptor<Project>()).filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor func entities(matching string: String) async throws -> [ProjectEntity] {
        let container = try Persistence.container()
        return try container.mainContext.fetch(FetchDescriptor<Project>()).filter { $0.name.localizedCaseInsensitiveContains(string) }.map { .init(id: $0.id, name: $0.name) }
    }
    @MainActor func suggestedEntities() async throws -> [ProjectEntity] {
        let container = try Persistence.container()
        return try container.mainContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.order)])).map { .init(id: $0.id, name: $0.name) }
    }
}
struct OverallStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Show overall project status"
    static var description = IntentDescription("Summarize stored progress and current monitoring evidence.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try Persistence.container(), context = container.mainContext
        let projects = try context.fetch(FetchDescriptor<Project>())
        let states = projects.map { $0.health().state }
        let progress = ProgressEngine.completion(projects.flatMap(\.tasks).map { .init(weight: $0.weight, completed: $0.status == .completed) })
        let text = "\(projects.count) projects. Development \(progress.formatted(.percent.precision(.fractionLength(0)))). \(states.filter { $0 == .healthy }.count) projects have fresh passing checks. \(states.filter { $0.severity >= 2 }.count) require attention. \(states.filter { $0 == .unknown }.count) have unknown health."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
struct ProjectsRequiringHelpIntent: AppIntent {
    static var title: LocalizedStringResource = "Show projects requiring help"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentNavigation.request("headquarter://help")
        return .result()
    }
}
struct ActiveTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Show active development tasks"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentNavigation.request("headquarter://tasks")
        return .result()
    }
}
struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open a project"
    static var openAppWhenRun = true
    @Parameter(title: "Project") var project: ProjectEntity
    @MainActor func perform() async throws -> some IntentResult {
        IntentNavigation.request("headquarter://project/\(project.id)")
        return .result()
    }
}
struct CreateTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Create a new task"
    static var description = IntentDescription("Add a persistent backlog task to a Head Quarter project.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Project") var project: ProjectEntity
    @Parameter(title: "Task title") var title: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try Persistence.container()
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        guard let match = projects.first(where: { $0.id == project.id }) else { throw IntentFailure.projectMissing }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 500 else { throw IntentFailure.invalidTitle }
        let task = WorkItem(title: cleanTitle)
        match.tasks.append(task)
        match.events.append(ActivityEvent(kind: .manualReport, message: "Task created: \(cleanTitle)", source: "Apple Shortcuts"))
        try container.mainContext.save()
        AppStore(container: container, connectWatch: false).publishSnapshot()
        return .result(dialog: IntentDialog(stringLiteral: "Created \(cleanTitle) in \(match.name)."))
    }
}
struct RecentErrorsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show recent errors"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        IntentNavigation.request("headquarter://errors")
        return .result()
    }
}
enum IntentFailure: LocalizedError {
    case projectMissing, invalidTitle
    var errorDescription: String? {
        switch self { case .projectMissing: return "The selected project no longer exists."; case .invalidTitle: return "Enter a task title between 1 and 500 characters." }
    }
}
struct HeadQuarterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OverallStatusIntent(), phrases: ["Show my project status in \(.applicationName)"], shortTitle: "Project status", systemImageName: "building.2")
        AppShortcut(intent: ProjectsRequiringHelpIntent(), phrases: ["Show projects requiring help in \(.applicationName)"], shortTitle: "Needs help", systemImageName: "hand.raised")
        AppShortcut(intent: ActiveTasksIntent(), phrases: ["Show active tasks in \(.applicationName)"], shortTitle: "Active tasks", systemImageName: "checklist")
        AppShortcut(intent: OpenProjectIntent(), phrases: ["Open a project in \(.applicationName)"], shortTitle: "Open project", systemImageName: "folder")
        AppShortcut(intent: CreateTaskIntent(), phrases: ["Create a task in \(.applicationName)"], shortTitle: "Create task", systemImageName: "plus.circle")
        AppShortcut(intent: RecentErrorsIntent(), phrases: ["Show recent errors in \(.applicationName)"], shortTitle: "Recent errors", systemImageName: "exclamationmark.triangle")
    }
}

@MainActor enum IntentNavigation {
    static func request(_ route: String) { UserDefaults.standard.set(route, forKey: "pendingRoute") }
}
