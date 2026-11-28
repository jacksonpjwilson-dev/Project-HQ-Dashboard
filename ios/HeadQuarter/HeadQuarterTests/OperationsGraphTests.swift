import XCTest
#if canImport(HeadQuarterCore)
@testable import HeadQuarterCore
#else
@testable import HeadQuarter
#endif

final class OperationsGraphTests: XCTestCase {
    func testRegistryContainsSevenBrandedSystemsAndValidDirectedEdges() throws {
        let systems = try EcosystemRegistry.load()
        XCTAssertEqual(Set(systems.map(\.id)), ["crew", "logbook", "hq", "ykf", "briefing", "stack", "stocked"])
        XCTAssertTrue(systems.allSatisfy { !$0.edges.isEmpty && $0.asset.hasPrefix("Brand") })
        XCTAssertTrue(systems.first { $0.id == "logbook" }!.summary.contains("Fitness"))
    }

    func testOwnerDisabledHealthKitRemainsExplicit() throws {
        let system = try XCTUnwrap(EcosystemRegistry.load().first { $0.id == "logbook" })
        XCTAssertNotNil(system.nodes.first { $0.id == "logbook.healthkit" }?.disabledReason)
    }

    func testDuplicateManifestSystemFails() throws {
        let system = try XCTUnwrap(EcosystemRegistry.load().first)
        XCTAssertThrowsError(try EcosystemRegistry.decode(JSONEncoder().encode([system, system])))
    }

    func testUnknownCoverageCannotBecomeHealthy() {
        XCTAssertEqual(OperationsHealth.aggregate([.healthy, .unknown]), .unknown)
        XCTAssertEqual(OperationsHealth.aggregate([.healthy, .missing]), .missing)
        XCTAssertEqual(OperationsHealth.aggregate([]), .unknown)
        XCTAssertEqual(OperationsHealth.aggregate([.disabled]), .disabled)
        XCTAssertEqual(OperationsHealth.aggregate([.disabled, .healthy]), .healthy)
    }

    func testFailurePrecedesGapsAndDegraded() {
        XCTAssertEqual(OperationsHealth.aggregate([.missing, .degraded, .failed]), .failed)
        XCTAssertEqual(OperationsHealth.aggregate([.unknown, .degraded]), .degraded)
    }

    func testExpiredObservationAndFutureClockAreUnknown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let observation = OperationObservation(state: .healthy, observedAt: now, checkedAt: now, expiry: 300,
                                              reason: "Feed published", source: "Test")
        XCTAssertEqual(observation.currentState(at: now.addingTimeInterval(299)), .healthy)
        XCTAssertEqual(observation.currentState(at: now.addingTimeInterval(301)), .unknown)
        XCTAssertEqual(observation.currentState(at: now.addingTimeInterval(-120)), .unknown)
    }

    func testDirectedDownstreamDoesNotTraverseDevelopmentOrLoop() {
        let edges = [
            OperationEdge(id: "ab", from: "a", to: "b", operation: "Read", owner: "Test", impact: "", domain: .runtime),
            OperationEdge(id: "bc", from: "b", to: "c", operation: "Save", owner: "Test", impact: "", domain: .runtime),
            OperationEdge(id: "ca", from: "c", to: "a", operation: "Return", owner: "Test", impact: "", domain: .runtime),
            OperationEdge(id: "bd", from: "b", to: "d", operation: "Build", owner: "Test", impact: "", domain: .development)
        ]
        XCTAssertEqual(OperationsHealth.downstream(of: "a", edges: edges), ["b", "c"])
    }

    func testStaleFlightPublicationNeverTurnsGreenOnNewHTTPRead() throws {
        let data = Data(#"{"generated":"2020-01-01T00:00:00Z","active":true,"rows":[],"feed":{"ok":true}}"#.utf8)
        let result = try PublicOperationsDecoder.decode(data, feed: "ykf", checkedAt: Date(), latency: 20)
        XCTAssertEqual(result.observations["ykf.feed-observer"]?.currentState(at: Date()), .unknown)
    }

    func testOffShiftIsNotActiveHeartbeat() throws {
        let data = Data(#"{"generated":"2026-01-01T00:00:00Z","active":false,"rows":[]}"#.utf8)
        let now = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        let result = try PublicOperationsDecoder.decode(data, feed: "ykf", checkedAt: now, latency: 20)
        XCTAssertEqual(result.observations["ykf.feed-observer"]?.currentState(at: now), .unknown)
    }

    func testMalformedPublicationIsRejected() {
        XCTAssertThrowsError(try PublicOperationsDecoder.decode(Data("{}".utf8), feed: "ykf", checkedAt: Date(), latency: 1))
        XCTAssertThrowsError(try PublicOperationsDecoder.decode(Data("{}".utf8), feed: "crew-activity", checkedAt: Date(), latency: 1))
    }

    func testActivityPreservesOriginalTimestampAndReportedOutcome() throws {
        let data = Data(#"{"date":"2026-11-19","generated":"09:15","items":[{"time":"09:00","from":"cal","to":"sunny","topic":"Schedule published"}]}"#.utf8)
        let now = ISO8601DateFormatter().date(from: "2026-11-19T15:00:00Z")!
        let result = try PublicOperationsDecoder.decode(data, feed: "crew-activity", checkedAt: now, latency: 20)
        XCTAssertEqual(result.activities.count, 1)
        XCTAssertEqual(result.activities.first?.state, .unknown)
        XCTAssertEqual(result.activities.first?.timestamp, ISO8601DateFormatter().date(from: "2026-11-19T14:00:00Z"))
    }

    func testDiagnosticSanitization() {
        let text = OperationsText.sanitized("Bearer abc123 token=secretvalue password=hunter2")
        XCTAssertFalse(text.contains("abc123"))
        XCTAssertFalse(text.contains("secretvalue"))
        XCTAssertFalse(text.contains("hunter2"))
    }
}

#if !SWIFT_PACKAGE
final class OperationsBindingTests: XCTestCase {
    @MainActor func testBindingDistinguishesMissingUnknownFailureAndPause() async throws {
        let defaults = UserDefaults(suiteName: "hq-operations-tests-" + UUID().uuidString)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("cache.json")
        let operations = OperationsStore(defaults: defaults, cacheURL: url)
        let container = try Persistence.container(inMemory: true)
        try Persistence.seed(container.mainContext)
        let store = AppStore(container: container, connectWatch: false)
        let system = try XCTUnwrap(operations.systems.first { $0.id == "briefing" })
        let project = try XCTUnwrap(operations.project(for: system, store: store))
        let node = try XCTUnwrap(system.nodes.first { $0.id == "briefing.calendar" })
        let service = MonitoredService(name: "Calendar reporting")
        project.services.append(service)
        XCTAssertEqual(operations.state(for: node, system: system, store: store, now: .now), .missing)
        operations.bind(service, to: node.id)
        XCTAssertEqual(operations.state(for: node, system: system, store: store, now: .now), .unknown)
        service.evidence = Evidence(state: .down, explanation: "Synthetic failed calendar fetch", observedAt: .now, source: "Regression fixture")
        XCTAssertEqual(operations.state(for: node, system: system, store: store, now: .now), .failed)
        operations.setPaused(true, target: node.id)
        XCTAssertEqual(operations.state(for: node, system: system, store: store, now: .now), .disabled)
        let restored = OperationsStore(defaults: defaults, cacheURL: url)
        XCTAssertTrue(restored.isPaused(node.id))
        XCTAssertEqual(restored.service(for: node.id, system: system, store: store)?.id, service.id)
    }

    @MainActor func testBrandAliasDoesNotRenameExistingWorkspace() async throws {
        let operations = OperationsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let container = try Persistence.container(inMemory: true)
        try Persistence.seed(container.mainContext)
        let store = AppStore(container: container, connectWatch: false)
        let system = try XCTUnwrap(operations.systems.first { $0.id == "stocked" })
        XCTAssertEqual(operations.project(for: system, store: store)?.name, "Pantry")
        store.route(URL(string: "headquarter://system/stocked")!)
        XCTAssertEqual(store.selectedTab, 1)
        XCTAssertEqual(store.projectPath.first, operations.project(for: system, store: store)?.id)
        XCTAssertEqual(operations.project(for: system, store: store)?.name, "Pantry")
    }

    @MainActor func testPublicAndDevelopmentEvidenceCannotCertifyRuntime() async throws {
        let operations = OperationsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                         cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let container = try Persistence.container(inMemory: true)
        try Persistence.seed(container.mainContext)
        let store = AppStore(container: container, connectWatch: false)
        let system = try XCTUnwrap(operations.systems.first { $0.id == "crew" })
        let project = try XCTUnwrap(operations.project(for: system, store: store))
        let service = MonitoredService(name: "Build", provider: "github", endpoint: system.repository)
        service.evidence = Evidence(state: .healthy, explanation: "Synthetic passing build", observedAt: .now, source: "Regression fixture")
        project.services.append(service)
        operations.bind(service, to: "crew.github-build")
        XCTAssertEqual(operations.state(for: system.edges.first { $0.id == "crew.github-build" }!,
                                         system: system, store: store, now: .now), .healthy)
        XCTAssertNotEqual(operations.state(for: system, store: store, now: .now), .healthy)
    }
}
#endif
