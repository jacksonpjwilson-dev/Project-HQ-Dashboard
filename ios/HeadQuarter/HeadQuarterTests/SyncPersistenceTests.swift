#if canImport(SwiftData) && canImport(HeadQuarter)
import XCTest
import SwiftData
@testable import HeadQuarter
private actor MemoryWorkspaceTransport: WorkspaceTransport {
    private var value = RemoteWorkspace(revision: 0, backup: nil)
    func fetch() async throws -> RemoteWorkspace { value }
    func save(_ backup: WorkspaceBackup, expectedRevision: Int) async throws -> RemoteWorkspace {
        guard expectedRevision == value.revision else { throw WorkspaceSyncError.remoteChanged }
        value = .init(revision: value.revision + 1, backup: backup); return value
    }
}
final class SyncPersistenceTests: XCTestCase {
    @MainActor func testReconciliationUpdatesExistingObjectsAndRemovesDeletedTasks() async throws {
        let container = try Persistence.container(inMemory: true), store = AppStore(container: container, isDemo: true)
        let project = Project(name: "Project", summary: ""), task = WorkItem(title: "Original"), removed = WorkItem(title: "Remove")
        project.tasks = [task, removed]; container.mainContext.insert(project); try container.mainContext.save()
        var backup = try BackupCodec.decode(BackupService.export([project]))
        backup.projects[0].tasks.removeAll { $0.id == removed.id }; backup.projects[0].tasks[0].title = "Remote edit"
        XCTAssertTrue(ArchiveReconciler.apply(backup, to: store))
        XCTAssertTrue(project.tasks[0] === task); XCTAssertEqual(task.title,"Remote edit")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<WorkItem>()),1)
    }
    @MainActor func testBidirectionalSyncMergesIndependentChanges() async throws {
        let container = try Persistence.container(inMemory: true), store = AppStore(container: container, connectWatch: false)
        let project = Project(name: "Project", summary: "Original"), task = WorkItem(title: "Task")
        project.tasks = [task]; container.mainContext.insert(project); try container.mainContext.save()
        let transport = MemoryWorkspaceTransport(), scope = "test:\(UUID())"
        await store.sync.synchronize(store: store,transport:transport,scope:scope)
        var remote = try await transport.fetch(); remote.backup!.projects[0].summary = "Remote summary"
        _ = try await transport.save(remote.backup!,expectedRevision:remote.revision)
        task.title = "Local title"; try container.mainContext.save()
        await store.sync.synchronize(store: store,transport:transport,scope:scope)
        XCTAssertEqual(project.summary,"Remote summary");XCTAssertEqual(task.title,"Local title")
        let result = try await transport.fetch()
        XCTAssertEqual(result.backup?.projects[0].tasks[0].title,"Local title")
    }
    @MainActor func testConflictPreservesLocalAndRemoteWork() async throws {
        let container = try Persistence.container(inMemory: true), store = AppStore(container: container, connectWatch: false)
        let project = Project(name: "Original",summary: "");container.mainContext.insert(project);try container.mainContext.save()
        let transport = MemoryWorkspaceTransport(), scope = "test:\(UUID())"
        await store.sync.synchronize(store: store,transport:transport,scope:scope)
        let before = try await transport.fetch();var remote = before.backup!;remote.projects[0].name = "Remote"
        _ = try await transport.save(remote,expectedRevision:before.revision)
        project.name = "Local";try container.mainContext.save()
        await store.sync.synchronize(store: store,transport:transport,scope:scope)
        XCTAssertEqual(project.name,"Local");let result = try await transport.fetch();XCTAssertEqual(result.backup?.projects[0].name,"Remote")
        XCTAssertNotNil(store.errorMessage)
    }
    func testCloudKitRequiresExplicitAppleConfiguration() async throws {
        let transport = CloudWorkspaceTransport(containerIdentifier:"iCloud.com.headquarter.app")
        do { _ = try await transport.fetch();XCTFail("Unconfigured CloudKit must not report success") }
        catch { XCTAssertTrue(error.localizedDescription.contains("CloudKit requires")) }
    }
}
#endif
