import XCTest
#if canImport(HeadQuarterCore)
@testable import HeadQuarterCore
#else
@testable import HeadQuarter
#endif

final class HealthEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func reading(_ state: Health?, age: TimeInterval = 0, critical: Bool = true, expiry: Double = 300) -> ServiceReading {
        .init(name: "API", critical: critical, expiry: expiry, evidence: state.map { .init(state: $0, explanation: "Verified HTTP response", observedAt: now.addingTimeInterval(-age), source: "Test monitor") })
    }
    func testUnconfiguredServiceIsUnknown() { XCTAssertEqual(HealthEngine.evaluate(reading(nil), now: now).state, .unknown) }
    func testNoServicesIsUnknown() { XCTAssertEqual(HealthEngine.aggregate([], now: now).state, .unknown) }
    func testFreshPassingEvidenceIsHealthy() { XCTAssertEqual(HealthEngine.evaluate(reading(.healthy), now: now).state, .healthy) }
    func testExpiredHeartbeatBecomesUnknownRatherThanDown() {
        XCTAssertEqual(HealthEngine.evaluate(reading(.healthy, age: 301), now: now).state, .unknown)
        XCTAssertEqual(HealthEngine.evaluate(reading(.down, age: 301), now: now).state, .unknown)
    }
    func testExpiryBoundary() {
        XCTAssertEqual(HealthEngine.evaluate(reading(.healthy, age: 300), now: now).state, .healthy)
        XCTAssertEqual(HealthEngine.evaluate(reading(.healthy, age: 300.01), now: now).state, .unknown)
    }
    func testFutureEvidenceIsNotTrusted() { XCTAssertEqual(HealthEngine.evaluate(reading(.healthy, age: -61), now: now).state, .unknown) }
    func testEmptyExplanationIsUnknown() {
        var sample = reading(.healthy); sample.evidence?.explanation = "  "
        XCTAssertEqual(HealthEngine.evaluate(sample, now: now).state, .unknown)
    }
    func testNoncriticalOutageIsAnError() { XCTAssertEqual(HealthEngine.evaluate(reading(.down, critical: false), now: now).state, .error) }
    func testAggregationRespectsSeverity() {
        XCTAssertEqual(HealthEngine.aggregate([reading(.healthy), reading(.needsHelp), reading(.error), reading(.down)], now: now).state, .down)
    }
    func testMissingCoveragePreventsGreen() {
        XCTAssertEqual(HealthEngine.aggregate([reading(.healthy), reading(nil)], now: now).state, .unknown)
    }
    func testConfirmedErrorWinsOverUnknown() {
        XCTAssertEqual(HealthEngine.aggregate([reading(nil), reading(.error)], now: now).state, .error)
    }
    func testOptionalPartialCoverageIsExplicit() {
        let result = HealthEngine.aggregate([reading(.healthy), reading(nil)], now: now, requireAll: false)
        XCTAssertEqual(result.state, .healthy)
        XCTAssertTrue(result.explanation.contains("incomplete coverage"))
    }
    func testAllUnknownWithPartialCoverageRemainsUnknown() { XCTAssertEqual(HealthEngine.aggregate([reading(nil)], now: now, requireAll: false).state, .unknown) }
    func testWidgetExpiresCachedHealthWithoutAnAppRefresh() {
        let snapshot = ProjectSnapshot(id: UUID(), name: "Project", health: .healthy, progress: 0.4, alerts: 0, evidenceAt: now, validUntil: now.addingTimeInterval(60))
        XCTAssertEqual(snapshot.currentHealth(at: now), .healthy)
        XCTAssertEqual(snapshot.currentHealth(at: now.addingTimeInterval(61)), .unknown)
    }
    func testSnapshotWithoutExpiryCannotBeGreen() {
        XCTAssertEqual(ProjectSnapshot(id: UUID(), name: "P", health: .healthy, progress: 1, alerts: 0, evidenceAt: now, validUntil: nil).currentHealth(at: now), .unknown)
    }
}
final class ProgressEngineTests: XCTestCase {
    func testNoTrackedWorkIsZero() { XCTAssertEqual(ProgressEngine.completion([]), 0) }
    func testWeightedCompletion() { XCTAssertEqual(ProgressEngine.completion([.init(weight: 3, completed: true), .init(weight: 1, completed: false)]), 0.75, accuracy: 0.00001) }
    func testAllCompleteIsOne() { XCTAssertEqual(ProgressEngine.completion([.init(weight: 3, completed: true), .init(weight: 7, completed: true)]), 1) }
    func testInvalidWeightsDoNotPoisonProgress() {
        XCTAssertEqual(ProgressEngine.completion([.init(weight: .nan, completed: true), .init(weight: .infinity, completed: true), .init(weight: -1, completed: true), .init(weight: 0, completed: true), .init(weight: 2, completed: false)]), 0)
    }
    func testLargeWeightsDoNotOverflow() { XCTAssertEqual(ProgressEngine.completion([.init(weight: .greatestFiniteMagnitude, completed: true), .init(weight: .greatestFiniteMagnitude, completed: false)]), 0.5) }
}
final class IncidentAndDependencyTests: XCTestCase {
    func testIncidentLifecycle() {
        XCTAssertTrue(IncidentState.open.canTransition(to: .acknowledged))
        XCTAssertTrue(IncidentState.open.canTransition(to: .resolved))
        XCTAssertTrue(IncidentState.acknowledged.canTransition(to: .resolved))
        XCTAssertFalse(IncidentState.resolved.canTransition(to: .open))
        XCTAssertFalse(IncidentState.acknowledged.canTransition(to: .open))
        XCTAssertFalse(IncidentState.resolved.canTransition(to: .resolved))
    }
    func testAcyclicDependencies() { let a = UUID(), b = UUID(); XCTAssertFalse(DependencyEngine.hasCycle([a: [b], b: []])) }
    func testIndirectDependencyCycle() { let a = UUID(), b = UUID(), c = UUID(); XCTAssertTrue(DependencyEngine.hasCycle([a: [b], b: [c], c: [a]])) }
    func testSelfDependencyCycle() { let id = UUID(); XCTAssertTrue(DependencyEngine.hasCycle([id: [id]])) }
}
final class BackupTests: XCTestCase {
    private func legacy(_ tasks: String = "[]") -> Data { Data("[{\"id\":1,\"name\":\"Logbook\",\"description\":\"Fitness\",\"status\":\"In development\",\"progress\":70,\"tasks\":\(tasks)}]".utf8) }
    func testLegacyFormatRetainsManualProgressAsHistory() throws {
        let backup = try BackupCodec.decode(legacy())
        XCTAssertEqual(backup.projects.first?.name, "Logbook")
        XCTAssertEqual(backup.projects.first?.phase, "Implementation")
        XCTAssertTrue(backup.projects[0].events[0].message.contains("70%"))
        XCTAssertTrue(backup.projects[0].services.isEmpty)
    }
    func testLegacyTaskCompletionMigratesWithoutInventedDates() throws {
        let tasks = "[{\"text\":\"Ship\",\"done\":true},{\"text\":\"Test\",\"done\":false}]"
        let backup = try BackupCodec.decode(legacy(tasks))
        XCTAssertEqual(backup.projects[0].tasks.map(\.status), [.completed, .backlog])
        XCTAssertNil(backup.projects[0].tasks[0].completedAt)
    }
    func testNativeRoundTrip() throws {
        let backup = try BackupCodec.decode(legacy())
        let copy = try BackupCodec.decode(BackupCodec.encode(backup))
        XCTAssertEqual(copy.projects[0].id, backup.projects[0].id)
        XCTAssertEqual(copy.projects[0].events[0].message, backup.projects[0].events[0].message)
    }
    func testUnsupportedVersionRejected() throws { var backup = try BackupCodec.decode(legacy()); backup.version = 500; XCTAssertThrowsError(try backup.validate()) }
    func testDuplicateObjectsRejected() throws { var backup = try BackupCodec.decode(legacy()); backup.projects.append(backup.projects[0]); XCTAssertThrowsError(try backup.validate()) }
    func testMalformedLegacyDoesNotSilentlyImport() { XCTAssertThrowsError(try BackupCodec.decode(Data("[{\"name\":\"bad\"}]".utf8))) }
    func testOversizedImportRejected() { XCTAssertThrowsError(try BackupCodec.decode(Data(repeating: 32, count: BackupCodec.maximumBytes + 1))) }
    func testInvalidDependencyRejectedBeforePersistence() throws {
        var backup = try BackupCodec.decode(legacy("[{\"text\":\"Task\",\"done\":false}]"))
        backup.projects[0].tasks[0].dependencyIDs = [UUID()]
        XCTAssertThrowsError(try backup.validate())
    }
    func testParentCycleRejected() throws {
        var backup = try BackupCodec.decode(legacy("[{\"text\":\"A\",\"done\":false},{\"text\":\"B\",\"done\":false}]"))
        backup.projects[0].tasks[0].parentID = backup.projects[0].tasks[1].id
        backup.projects[0].tasks[1].parentID = backup.projects[0].tasks[0].id
        XCTAssertThrowsError(try backup.validate())
    }
}
final class ProviderValidationTests: XCTestCase {
    func testEndpointRejectsInsecureURL() async {
        do { _ = try await EndpointProvider().check(.init(id: UUID(), endpoint: "http://example.com", timeout: 5, credential: nil)); XCTFail("Expected validation failure") }
        catch { XCTAssertEqual(error as? MonitoringError, .invalidURL) }
    }
    func testEndpointRejectsEmbeddedCredentials() async {
        do { _ = try await EndpointProvider().check(.init(id: UUID(), endpoint: "https://user:password@example.com", timeout: 5, credential: nil)); XCTFail("Expected validation failure") }
        catch { XCTAssertEqual(error as? MonitoringError, .invalidURL) }
    }
    func testGitHubRejectsHostInjection() async {
        do { _ = try await GitHubActionsProvider().check(.init(id: UUID(), endpoint: "evil.test/owner/repo", timeout: 5, credential: "secret")); XCTFail("Expected validation failure") }
        catch { XCTAssertEqual(error as? MonitoringError, .invalidURL) }
    }
    func testRelayRequiresCredential() async {
        do { _ = try await RelayProvider().check(.init(id: UUID(), endpoint: "https://example.com", timeout: 5, credential: nil)); XCTFail("Expected authentication failure") }
        catch { XCTAssertEqual(error as? MonitoringError, .authentication) }
    }
    func testRelayEvidenceIsBoundToService() {
        let id = UUID(), now = Date.now
        let envelope = RelayEvidenceEnvelope(version: 1, serviceID: id, evidence: .init(state: .healthy, explanation: "Signed event", observedAt: now, source: "Relay"))
        XCTAssertNoThrow(try envelope.validate(expectedServiceID: id, now: now))
        XCTAssertThrowsError(try envelope.validate(expectedServiceID: UUID(), now: now))
    }
}

final class RateLimitAndWorkflowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testRetryAfterSeconds() { XCTAssertEqual(RateLimitPolicy.retryDate(headers: ["Retry-After": "120"], now: now), now.addingTimeInterval(120)) }
    func testGitHubResetHeader() { XCTAssertEqual(RateLimitPolicy.retryDate(headers: ["X-RateLimit-Reset": "1800003600"], now: now), now.addingTimeInterval(3600)) }
    func testInvalidBackoffDefaultsToFifteenMinutes() { XCTAssertEqual(RateLimitPolicy.retryDate(headers: ["Retry-After": "garbage"], now: now), now.addingTimeInterval(900)) }
    func testBackoffIsBounded() { XCTAssertEqual(RateLimitPolicy.retryDate(headers: ["Retry-After": "99999999999"], now: now), now.addingTimeInterval(86400)) }
    private func workflow(status: String, conclusion: String) throws -> Evidence {
        let body = "{\"workflow_runs\":[{\"status\":\"\(status)\",\"conclusion\":\(conclusion),\"updated_at\":\"2026-01-01T12:00:00Z\",\"name\":\"CI\"}]}"
        return try GitHubActionsProvider.decodeEvidence(Data(body.utf8))
    }
    func testRunningBuildDoesNotClaimManualInterventionIsNeeded() throws { XCTAssertEqual(try workflow(status: "in_progress", conclusion: "null").state, .unknown) }
    func testApprovalWaitingBuildRequiresHelp() throws { XCTAssertEqual(try workflow(status: "waiting", conclusion: "null").state, .needsHelp) }
    func testSuccessfulBuildKeepsItsOriginalEvidenceDate() throws {
        let evidence = try workflow(status: "completed", conclusion: "\"success\"")
        XCTAssertEqual(evidence.state, .healthy)
        XCTAssertEqual(evidence.observedAt, ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z"))
        XCTAssertEqual(HealthEngine.evaluate(.init(name: "CI", critical: false, expiry: 300, evidence: evidence), now: now).state, .unknown)
    }
    func testCancelledBuildDoesNotClaimAnOutage() throws { XCTAssertEqual(try workflow(status: "completed", conclusion: "\"cancelled\"").state, .unknown) }
    func testFailedBuildIsAnError() throws { XCTAssertEqual(try workflow(status: "completed", conclusion: "\"failure\"").state, .error) }
}

final class EndpointCriteriaTests: XCTestCase {
    private func evaluate(status: Int, body: String, marker: String = "") -> Evidence {
        let config = MonitorConfiguration(id: UUID(), endpoint: "https://example.com/health", timeout: 5, credential: nil, expectedHTTPStatus: 200, requiredBodyText: marker)
        return EndpointProvider.evaluate(status: status, body: Data(body.utf8), configuration: config, source: "Test", now: .now)
    }
    func testExpectedStatusPasses() { XCTAssertEqual(evaluate(status: 200, body: "ok").state, .healthy) }
    func testUnexpectedSuccessStatusFailsConfiguredCriteria() { XCTAssertEqual(evaluate(status: 204, body: "").state, .error) }
    func testLoginPageDoesNotPassRequiredBodyAssertion() { XCTAssertEqual(evaluate(status: 200, body: "Sign in", marker: "service-ready").state, .error) }
    func testVerifiedBodyAssertionPasses() { XCTAssertEqual(evaluate(status: 200, body: "service-ready", marker: "service-ready").state, .healthy) }
    func testServerFailureIsDownBeforeCriticalityAggregation() { XCTAssertEqual(evaluate(status: 503, body: "Unavailable").state, .down) }
    func testLongDependencyChainDoesNotUseTheCallStack() {
        let ids = (0..<10_000).map { _ in UUID() }
        var graph = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in (id, index + 1 < ids.count ? [ids[index + 1]] : []) })
        XCTAssertFalse(DependencyEngine.hasCycle(graph))
        graph[ids.last!] = [ids[0]]
        XCTAssertTrue(DependencyEngine.hasCycle(graph))
    }
}

final class ComponentSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func reading(_ state: Health, expiry: Double) -> ServiceReading {
        .init(name: state.rawValue, critical: true, expiry: expiry, evidence: .init(state: state, explanation: "Verified result", observedAt: now, source: "Monitor"))
    }
    private func snapshot(_ readings: [ServiceReading], requireAll: Bool = true) -> ProjectSnapshot {
        .init(id: UUID(), name: "Project", health: .healthy, progress: 0, alerts: 0, evidenceAt: now, validUntil: now.addingTimeInterval(60), readings: readings, requireAllChecks: requireAll)
    }
    func testExpiredPassingCheckDoesNotHideFreshCriticalFailure() {
        let value = snapshot([reading(.healthy, expiry: 60), reading(.down, expiry: 600)])
        XCTAssertEqual(value.currentHealth(at: now.addingTimeInterval(61)), .down)
    }
    func testExpiryRevealsRemainingFreshLowerSeverityEvidence() {
        let value = snapshot([reading(.down, expiry: 60), reading(.error, expiry: 600)])
        XCTAssertEqual(value.currentHealth(at: now.addingTimeInterval(61)), .error)
    }
    func testAllExpiredComponentsAreUnknown() {
        let value = snapshot([reading(.healthy, expiry: 60), reading(.error, expiry: 60)])
        XCTAssertEqual(value.currentHealth(at: now.addingTimeInterval(61)), .unknown)
    }
    func testSnapshotPreservesExplicitPartialCoverageRule() {
        let value = snapshot([reading(.unknown, expiry: 60), reading(.healthy, expiry: 600)], requireAll: false)
        XCTAssertEqual(value.currentHealth(at: now.addingTimeInterval(61)), .healthy)
    }
}
