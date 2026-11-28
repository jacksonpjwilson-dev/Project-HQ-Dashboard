import SwiftUI
import SwiftData
import UserNotifications

@main struct HeadQuarterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: AppStore?
    @State private var launchError: String?
    @State private var pendingURL: URL?
    @State private var showingOpening = true
    var body: some Scene {
        WindowGroup {
            Group {
                if let store { RootView().environment(store).modelContainer(store.container) }
                else if let launchError {
                    ContentUnavailableView {
                        Label("Could not open your workspace", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(launchError + " Your stored data has not been deleted.") }
                    actions: { Button("Try again") { openWorkspace() } }
                } else { ProgressView("Opening Head Quarter…").task { openWorkspace() } }
            }
            .overlay {
                if showingOpening {
                    OpeningAnimationView {
                        withAnimation(.easeOut(duration: 0.2)) { showingOpening = false }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .statusBarHidden(showingOpening)
            .onOpenURL { url in if let store { store.route(url) } else { pendingURL = url } }
        }
    }
    @MainActor private func openWorkspace() {
        do {
            let container = try Persistence.container()
            try Persistence.seed(container.mainContext)
            let workspace = AppStore(container: container)
            store = workspace; launchError = nil
            appDelegate.configure(workspace)
            if let pendingURL { workspace.route(pendingURL); self.pendingURL = nil }
        } catch { launchError = error.localizedDescription }
    }
}
