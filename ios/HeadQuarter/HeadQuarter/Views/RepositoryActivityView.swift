import SwiftUI
struct RepositoryActivityView: View {
    @Environment(AppStore.self) private var store
    var project: Project
    var service: MonitoredService
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            List {
                if let cache = store.cachedActivity(serviceID: service.id), let activity = cache.activity, activity.repository == service.endpoint {
                    Section {
                        let stale = timeline.date.timeIntervalSince(activity.fetchedAt) > service.expiry
                        Label(stale ? "Cached activity · stale" : "Fetched repository activity", systemImage: stale ? "clock.badge.exclamationmark" : "arrow.triangle.branch")
                        Text(activity.fetchedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        Text("Workflow status is independent of app availability and manually tracked development completion.").font(.caption)
                        if let error = cache.errorMessage { Text("Latest refresh failed: \(error)").font(.caption).foregroundStyle(.orange) }
                    }
                    Section("Recent commits · latest 30") { ForEach(activity.commits) { commit in
                        Link(destination: commit.url) { VStack(alignment: .leading, spacing: 4) { Text(commit.message).lineLimit(3); Text("\(commit.id.prefix(7)) · \(commit.author) · \(commit.date.formatted())").font(.caption).foregroundStyle(.secondary) } }
                    } }
                    Section("Pull requests · latest 30 updated") { ForEach(activity.pullRequests) { pull in
                        Link(destination: pull.url) { VStack(alignment: .leading, spacing: 4) { Text("#\(pull.id) \(pull.title)"); Text("\(pull.draft ? "Draft · " : "")\(pull.state) · \(pull.updatedAt.formatted())").font(.caption).foregroundStyle(.secondary) } }
                    } }
                } else { ContentUnavailableView("No fetched repository activity", systemImage: "arrow.triangle.branch", description: Text("Configure owner/repository and an optional read token in the GitHub service, then refresh. No example activity is shown as live.")) }
            }
        }.navigationTitle(service.endpoint)
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(project: project) } }.disabled(store.isRefreshing || store.isDemo) }
            .safeAreaInset(edge: .bottom) { WorkspaceErrorBanner() }
    }
}
