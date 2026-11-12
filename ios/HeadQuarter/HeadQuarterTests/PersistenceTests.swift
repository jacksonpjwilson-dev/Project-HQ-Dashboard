#if canImport(SwiftData) && canImport(HeadQuarter)
import XCTest
import SwiftData
@testable import HeadQuarter
final class PersistenceTests: XCTestCase {
    @MainActor func testSevenSeededProjectsAndSeedIsIdempotent() async throws {
        let container = try Persistence.container(inMemory: true)
        try Persistence.seed(container.mainContext); try Persistence.seed(container.mainContext)
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(Set(projects.map(\.name)), Set(["Logbook", "Daily Briefing", "Stack", "Crew", "YKF Arrivals", "Pantry", "Head Quarter"]))
        XCTAssertEqual(projects.count, 7)
        XCTAssertTrue(projects.allSatisfy { $0.health().state == .unknown && $0.progress == 0 })
    }
    @MainActor func testDeletingAllProjectsDoesNotReseed() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        try Persistence.seed(context)
        for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
        try context.save(); try Persistence.seed(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
    }
    @MainActor func testTaskRelationshipAndWeightedProgressPersist() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        let project = Project(name: "Test", summary: "")
        let complete = WorkItem(title: "Complete"); complete.status = .completed; complete.weight = 3
        let pending = WorkItem(title: "Pending"); pending.weight = 1
        project.tasks = [complete, pending]; context.insert(project); try context.save()
        let loaded = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(loaded.tasks.count, 2); XCTAssertEqual(loaded.progress, 0.75)
    }
    @MainActor func testIncidentRepeatedEvidenceAndRecovery() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        let store = AppStore(container: container, isDemo: true)
        let project = Project(name: "API", summary: ""), service = MonitoredService(name: "Health")
        project.services.append(service); context.insert(project); try context.save()
        let failed = Evidence(state: .down, explanation: "HTTP 503", observedAt: .now, source: "Monitor")
        store.record(failed, for: service, in: project)
        store.record(failed, for: service, in: project)
        XCTAssertEqual(project.incidents.count, 1); XCTAssertEqual(project.events.count, 1)
        let incident = try XCTUnwrap(project.incidents.first)
        XCTAssertTrue(incident.transition(to: .acknowledged)); try context.save()
        store.record(.init(state: .down, explanation: "Still failing", observedAt: .now, source: "Monitor"), for: service, in: project)
        XCTAssertEqual(project.incidents.count, 1); XCTAssertEqual(incident.state, .acknowledged)
        store.record(.init(state: .healthy, explanation: "HTTP 200", observedAt: .now, source: "Monitor"), for: service, in: project)
        XCTAssertEqual(incident.state, .resolved)
        store.record(.init(state: .down, explanation: "New failure", observedAt: .now, source: "Monitor"), for: service, in: project)
        XCTAssertEqual(project.incidents.count, 2)
    }
    @MainActor func testProjectDeletionCascades() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        let project = Project(name: "Delete", summary: ""); project.tasks = [WorkItem(title: "Child")]
        context.insert(project); try context.save(); context.delete(project); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkItem>()), 0)
    }
    @MainActor func testBackupRestorePreservesDataAndRejectsOverwrite() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        let project = Project(name: "Backup", summary: "Preserve me"); project.tasks = [WorkItem(title: "Important")]
        context.insert(project); try context.save()
        let backup = try BackupCodec.decode(BackupService.export([project]))
        let other = AppStore(container: try Persistence.container(inMemory: true), isDemo: true)
        XCTAssertTrue(BackupService.restore(backup, store: other)); XCTAssertEqual(other.projects.first?.tasks.first?.title, "Important")
        XCTAssertFalse(BackupService.restore(backup, store: other)); XCTAssertEqual(other.projects.count, 1)
    }
    @MainActor func testBackupChildIdentifierCollisionCannotOverwriteExistingTask() async throws {
        let container = try Persistence.container(inMemory: true), context = container.mainContext
        let project = Project(name: "Original", summary: ""); project.tasks = [WorkItem(title: "Must remain")]
        context.insert(project); try context.save()
        var backup = try BackupCodec.decode(BackupService.export([project]))
        backup.projects[0].id = UUID(); backup.projects[0].tasks[0].title = "Attempted overwrite"
        let store = AppStore(container: container, isDemo: true)
        XCTAssertFalse(BackupService.restore(backup, store: store))
        XCTAssertEqual(project.tasks[0].title, "Must remain")
    }

    @MainActor func testAttentionIncludesFailedWorkAndResolvedButStillDownServices() async throws {
        let project = Project(name: "Attention", summary: "")
        XCTAssertFalse(project.requiresAttention)
        let task = WorkItem(title: "Failed build task"); task.status = .failed; project.tasks = [task]
        XCTAssertTrue(project.requiresAttention)
        task.status = .completed
        let service = MonitoredService(name: "API")
        service.evidence = .init(state: .down, explanation: "HTTP 503", observedAt: .now, source: "Test")
        project.services = [service]
        XCTAssertTrue(project.requiresAttention)
    }

}
#endif
