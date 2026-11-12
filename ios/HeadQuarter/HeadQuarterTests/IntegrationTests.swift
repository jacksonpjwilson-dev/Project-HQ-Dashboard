import XCTest
#if canImport(HeadQuarterCore)
@testable import HeadQuarterCore
#else
@testable import HeadQuarter
#endif
final class WorkspaceMergeTests: XCTestCase {
    private func fixture() throws -> WorkspaceBackup {
        try BackupCodec.decode(Data("[{\"id\":1,\"name\":\"Project\",\"description\":\"Original\",\"status\":\"Planning\",\"progress\":0,\"tasks\":[{\"text\":\"Task\",\"done\":false}]}]".utf8))
    }
    func testIndependentTaskAndProjectFieldsMerge() throws {
        let base = try fixture(); var local = base, remote = base
        local.projects[0].tasks[0].title = "Local title"; remote.projects[0].summary = "Remote summary"
        let result = try WorkspaceMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.projects[0].tasks[0].title, "Local title"); XCTAssertEqual(result.projects[0].summary, "Remote summary")
    }
    func testSameFieldConflictStopsInsteadOfOverwriting() throws {
        let base = try fixture(); var local = base, remote = base
        local.projects[0].tasks[0].title = "Local"; remote.projects[0].tasks[0].title = "Remote"
        XCTAssertThrowsError(try WorkspaceMerge.merge(base: base, local: local, remote: remote))
    }
    func testRemoteDeletionAndLocalUnchangedIsPreserved() throws {
        let base = try fixture(); var remote = base; remote.projects[0].tasks = []
        XCTAssertTrue(try WorkspaceMerge.merge(base: base, local: base, remote: remote).projects[0].tasks.isEmpty)
    }
    func testDeletionVersusEditedTaskIsAConflict() throws {
        let base = try fixture(); var local = base, remote = base
        local.projects[0].tasks = []; remote.projects[0].tasks[0].title = "Important edit"
        XCTAssertThrowsError(try WorkspaceMerge.merge(base: base, local: local, remote: remote))
    }
    func testFirstSyncDoesNotDiscardLocalWork() throws {
        let local = try fixture()
        let result = try WorkspaceMerge.merge(base: nil, local: local, remote: nil)
        XCTAssertTrue(try WorkspaceMerge.equivalent(result, local))
    }
    func testDifferentNewProjectsMerge() throws {
        let local = try fixture(), remote = try fixture()
        XCTAssertEqual(try WorkspaceMerge.merge(base: nil, local: local, remote: remote).projects.count, 2)
    }
    func testRecordOrderingDoesNotCreateFalseChanges() throws {
        var a = try fixture(); a.projects += try fixture().projects
        var b = a; b.projects.reverse(); b.exportedAt = .now.addingTimeInterval(100)
        XCTAssertTrue(try WorkspaceMerge.equivalent(a,b))
    }
    func testNewTasksMergeByID() throws {
        let base = try fixture(); var local = base, remote = base
        var a = base.projects[0].tasks[0]; a.id = UUID(); a.title = "A"
        var b = a; b.id = UUID(); b.title = "B"
        local.projects[0].tasks.append(a); remote.projects[0].tasks.append(b)
        XCTAssertEqual(try WorkspaceMerge.merge(base: base, local: local, remote: remote).projects[0].tasks.count,3)
    }
}
final class GitHubRepositoryTests: XCTestCase {
    func testRealAPIShapesPreserveDatesAndMergedState() throws {
        let commits=Data("[{\"sha\":\"abcdef\",\"html_url\":\"https://github.com/owner/repo/commit/abcdef\",\"commit\":{\"message\":\"Change\",\"author\":{\"name\":\"Developer\",\"date\":\"2026-01-01T12:00:00Z\"}}}]".utf8)
        let pulls=Data("[{\"number\":1,\"title\":\"PR\",\"state\":\"closed\",\"merged_at\":\"2026-01-02T12:00:00Z\",\"updated_at\":\"2026-01-02T12:00:00Z\",\"html_url\":\"https://github.com/owner/repo/pull/1\"}]".utf8)
        let result=try GitHubRepositoryProvider.decode(repository:"owner/repo",commits:commits,pulls:pulls,runs:Data("{\"workflow_runs\":[]}".utf8),now:.now)
        XCTAssertEqual(result.commits[0].author,"Developer");XCTAssertEqual(result.pullRequests[0].state,"merged");XCTAssertEqual(result.workflow.state,.unknown)
    }
    func testRepositoryHostInjectionRejected() async {
        do { _ = try await GitHubRepositoryProvider().fetch(repository:"evil.test/owner/repo",token:nil);XCTFail() } catch { XCTAssertEqual(error as? MonitoringError,.invalidURL) }
    }
    func testLivePublicRepositoryWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["HQ_RUN_GITHUB_LIVE"] == "1" else { throw XCTSkip("Live API calls require explicit opt-in") }
        let result = try await GitHubRepositoryProvider().fetch(repository:"jacksonpjwilson-dev/Project-HQ-Dashboard",token:nil)
        XCTAssertFalse(result.commits.isEmpty);XCTAssertTrue(result.pullRequests.contains { $0.id == 1 })
    }
}

final class WatchPayloadBudgetTests: XCTestCase {
    func testLargeSnapshotFitsWatchConnectivityBudgetAndLabelsTruncation() throws {
        let now = Date.now
        let readings = (0..<1000).map { _ in ServiceReading(name: "Service",critical: true,expiry: 60,evidence: .init(state: .healthy,explanation: String(repeating: "X",count: 4000),observedAt: now,source: "Monitor")) }
        let project = ProjectSnapshot(id: UUID(),name:"Large",health:.healthy,progress:0.5,alerts:0,evidenceAt:now,validUntil:now.addingTimeInterval(60),readings:readings)
        let value = WatchPayload(dashboard:.init(generatedAt:now,projects:[project]),tasks:[],incidents:[])
        let data = try value.boundedData();XCTAssertLessThan(data.count,60000)
        let result = try JSONDecoder().decode(WatchPayload.self,from:data)
        XCTAssertEqual(result.truncated,true);XCTAssertEqual(result.dashboard.projects[0].currentHealth(at:now),.unknown)
    }
}

final class WatchOverallHealthTests: XCTestCase {
    func testTruncatedCoverageCannotClaimAllSystemsHealthy() {
        let now = Date.now
        let project = ProjectSnapshot(id:UUID(),name:"P",health:.healthy,progress:0,alerts:0,evidenceAt:now,validUntil:now.addingTimeInterval(60))
        let value = WatchPayload(dashboard:.init(generatedAt:now,projects:[project]),tasks:[],incidents:[],truncated:true)
        XCTAssertEqual(value.overallHealth(at:now),.unknown)
    }
    func testFreshCriticalFailureWinsOverIncompleteCoverage() {
        let now = Date.now
        let project = ProjectSnapshot(id:UUID(),name:"P",health:.down,progress:0,alerts:1,evidenceAt:now,validUntil:now.addingTimeInterval(60))
        let value = WatchPayload(dashboard:.init(generatedAt:now,projects:[project]),tasks:[],incidents:[],truncated:true)
        XCTAssertEqual(value.overallHealth(at:now),.down)
    }
}

final class FeedFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:1_800_000_000)
    private func evidence(_ body: String) -> Evidence {
        EndpointProvider.evaluate(status:200,body:Data(body.utf8),configuration:.init(id:UUID(),endpoint:"https://example.com",timeout:5,credential:nil,timestampPath:"meta.updatedAt"),source:"Test",now:now)
    }
    func testFreshProducerTimestampPasses() { XCTAssertEqual(HealthEngine.evaluate(.init(name:"Feed",critical:true,expiry:300,evidence:evidence("{\"meta\":{\"updatedAt\":1800000000}}")),now:now).state,.healthy) }
    func testStaleDataDoesNotBecomeFreshFromAnotherHTTP200() { XCTAssertEqual(HealthEngine.evaluate(.init(name:"Feed",critical:true,expiry:300,evidence:evidence("{\"meta\":{\"updatedAt\":1799990000}}")),now:now).state,.unknown) }
    func testMissingTimestampRequiresConfigurationHelp() { XCTAssertEqual(evidence("{}").state,.needsHelp) }
    func testFutureTimestampIsUnknown() { XCTAssertEqual(evidence("{\"meta\":{\"updatedAt\":1800010000}}").state,.unknown) }
    func testBooleanIsNotEpochSeconds() { XCTAssertEqual(evidence("{\"meta\":{\"updatedAt\":true}}").state,.needsHelp) }
}

final class WatchUnicodeBudgetTests: XCTestCase {
    func testCombiningUnicodeCannotDefeatTheByteBudget() throws {
        let now = Date.now, name = "a" + String(repeating:"\u{301}",count:40000)
        let project = ProjectSnapshot(id:UUID(),name:name,health:.unknown,progress:0,alerts:0,evidenceAt:nil,validUntil:nil)
        let value = WatchPayload(dashboard:.init(generatedAt:now,projects:[project]),tasks:[],incidents:[])
        XCTAssertLessThan(try value.boundedData().count,60000)
    }
}
