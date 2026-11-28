import Foundation
import Observation
import SwiftData
import UserNotifications
import WatchConnectivity

@MainActor @Observable final class OperationsStore {
    private(set) var systems: [SystemDefinition] = []
    private(set) var cache = OperationsCache()
    private(set) var checking = Set<String>()
    private(set) var error: String?
    private(set) var refreshing = false
    private var bindings: [String: String] = [:]
    private var paused = Set<String>()
    private let defaults: UserDefaults
    private let cacheURL: URL

    init(defaults: UserDefaults = .standard, cacheURL: URL? = nil) {
        self.defaults = defaults
        self.cacheURL = cacheURL ?? URL.applicationSupportDirectory.appending(path: "Operations/evidence.json")
        do { systems = try EcosystemRegistry.load() }
        catch { self.error = "The operations registry could not be read." }
        if let data = try? Data(contentsOf: self.cacheURL) {
            do { cache = try JSONDecoder().decode(OperationsCache.self, from: data) }
            catch { self.error = "Saved operations evidence is unreadable. Refresh to recover; workspace data is unaffected." }
        }
        bindings = defaults.dictionary(forKey: "operations.bindings") as? [String: String] ?? [:]
        paused = Set(defaults.stringArray(forKey: "operations.paused") ?? [])
    }

    func project(for system: SystemDefinition, store: AppStore) -> Project? {
        store.projects.first { system.matches($0.name) }
    }

    func service(for target: String, system: SystemDefinition, store: AppStore) -> MonitoredService? {
        guard let id = bindings[target] else { return nil }
        return project(for: system, store: store)?.services.first { $0.id.uuidString == id }
    }

    func bind(_ service: MonitoredService?, to target: String) {
        bindings[target] = service?.id.uuidString
        defaults.set(bindings, forKey: "operations.bindings")
    }

    func isPaused(_ target: String) -> Bool { paused.contains(target) }
    func setPaused(_ value: Bool, target: String) {
        if value { paused.insert(target) } else { paused.remove(target) }
        defaults.set(Array(paused), forKey: "operations.paused")
    }

    func observation(for target: String, system: SystemDefinition, store: AppStore) -> OperationObservation? {
        if let service = service(for: target, system: system, store: store), let evidence = service.evidence {
            return .init(state: OperationsHealth.state(evidence.state), observedAt: evidence.observedAt,
                         checkedAt: service.lastCheckedAt ?? evidence.observedAt, expiry: service.expiry,
                         reason: OperationsText.sanitized(evidence.explanation), source: OperationsText.sanitized(evidence.source),
                         lastSuccess: evidence.state == .healthy ? evidence.observedAt : nil,
                         lastFailure: evidence.state == .error || evidence.state == .down ? evidence.observedAt : nil)
        }
        return cache.observations[target]
    }

    func state(for node: OperationNode, system: SystemDefinition, store: AppStore, now: Date) -> ConnectionState {
        if node.disabledReason != nil || isPaused(node.id) { return .disabled }
        if let observation = observation(for: node.id, system: system, store: store) { return observation.currentState(at: now) }
        if service(for: node.id, system: system, store: store) != nil { return .unknown }
        return node.required ? .missing : .unknown
    }

    func state(for edge: OperationEdge, system: SystemDefinition, store: AppStore, now: Date) -> ConnectionState {
        if isPaused(edge.id) || system.nodes.first(where: { $0.id == edge.from })?.disabledReason != nil { return .disabled }
        if let observation = observation(for: edge.id, system: system, store: store) { return observation.currentState(at: now) }
        if service(for: edge.id, system: system, store: store) != nil { return .unknown }
        return .missing
    }

    func state(for system: SystemDefinition, store: AppStore, now: Date) -> ConnectionState {
        // Public availability and development checks never establish another app's runtime.
        let runtime = system.nodes.filter { $0.required && $0.kind != "development" && $0.kind != "monitor" }
        return OperationsHealth.aggregate(runtime.map { state(for: $0, system: system, store: store, now: now) })
    }

    func events(for system: SystemDefinition?, store: AppStore) -> [OperationActivity] {
        let selected = system.map { [$0] } ?? systems
        let native = selected.flatMap { spec in
            (project(for: spec, store: store)?.events ?? []).map { event in
                OperationActivity(id: event.id.uuidString, systemID: spec.id, targetID: event.serviceID?.uuidString ?? "",
                                  timestamp: event.timestamp, actor: OperationsText.sanitized(event.source),
                                  message: OperationsText.sanitized(event.message),
                                  state: [.taskFailed, .buildFailed, .healthCheckFailed, .integrationDisconnected].contains(event.kind) ? .failed : .unknown)
            }
        }
        return (native + cache.activities.filter { system == nil || $0.systemID == system?.id })
            .sorted { $0.timestamp > $1.timestamp }
    }

    func refresh(system: SystemDefinition? = nil, store: AppStore, includeBoundServices: Bool = true) async {
        guard !refreshing, !store.isDemo else { return }
        refreshing = true
        defer { refreshing = false; checking.removeAll() }
        error = nil
        let chosen = system.map { [$0] } ?? systems
        let feeds: [(String, String, String, String)] = [
            ("crew", "crew-roster", "crew.roster-observer", "https://raw.githubusercontent.com/jacksonpjwilson-dev/crew-map/data/roster.json"),
            ("crew", "crew-activity", "crew.activity-observer", "https://raw.githubusercontent.com/jacksonpjwilson-dev/crew-map/data/activity.json"),
            ("ykf", "ykf", "ykf.feed-observer", "https://raw.githubusercontent.com/jacksonpjwilson-dev/ykf-tracker/data/live.json")
        ]
        for (systemID, feed, target, address) in feeds where chosen.contains(where: { $0.id == systemID }) && !isPaused(target) {
            checking.insert(target)
            let start = Date.now
            let previousObservation = cache.observations[target]
            do {
                let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
                defer { session.finishTasksAndInvalidate() }
                var request = URLRequest(url: URL(string: address)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw MonitoringError.badResponse }
                if http.statusCode == 401 || http.statusCode == 403 { throw MonitoringError.authentication }
                if http.statusCode == 429 { throw MonitoringError.rateLimited(until: Date.now.addingTimeInterval(300)) }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                guard data.count <= 1_500_000 else { throw MonitoringError.invalidPayload }
                let result = try PublicOperationsDecoder.decode(data, feed: feed, checkedAt: .now,
                                                                latency: Int(Date.now.timeIntervalSince(start) * 1000))
                cache.observations.merge(result.observations) { previous, fresh in
                    var updated = fresh
                    updated.lastFailure = previous.lastFailure
                    return updated
                }
                if let agents = result.agents { cache.agents = agents }
                if let observation = result.observations[target],
                   previousObservation?.state != observation.state || previousObservation?.reason != observation.reason {
                    cache.activities.append(.init(id: "check|\(target)|\(observation.checkedAt.timeIntervalSince1970)",
                                                  systemID: systemID, targetID: target, timestamp: observation.checkedAt,
                                                  actor: "Headquarters public-feed adapter",
                                                  message: observation.explanation(at: observation.checkedAt),
                                                  state: observation.currentState(at: observation.checkedAt)))
                }
                cache.observations[target.replacingOccurrences(of: "-observer", with: "")] = result.observations[target]
                var ids = Set(cache.activities.map(\.id))
                cache.activities += result.activities.filter { ids.insert($0.id).inserted }
            } catch {
                let previous = cache.observations[target]
                cache.observations[target] = .init(state: .unknown, observedAt: .now, checkedAt: .now, expiry: 300,
                                                   reason: "Read failed. Check connectivity and retry. " + OperationsText.sanitized(error.localizedDescription),
                                                   source: "HQ public-feed request", lastSuccess: previous?.lastSuccess, lastFailure: .now)
                if previous?.lastFailure == nil {
                    cache.activities.append(.init(id: "check|\(target)|\(Date.now.timeIntervalSince1970)",
                                                  systemID: systemID, targetID: target, timestamp: .now,
                                                  actor: "Headquarters public-feed adapter",
                                                  message: "Public read failed; application availability remains unknown.", state: .failed))
                }
                self.error = "Some feed checks failed. Prior activity is retained and successful checks remain available."
            }
            checking.remove(target)
        }
        for spec in chosen where includeBoundServices {
            guard let project = project(for: spec, store: store) else { continue }
            let targets = Set((spec.nodes.map(\.id) + spec.edges.map(\.id)).filter { !isPaused($0) })
            let ids = Set(targets.compactMap { bindings[$0] })
            for service in project.services where ids.contains(service.id.uuidString) {
                checking.formUnion(targets.filter { bindings[$0] == service.id.uuidString })
                await store.check(service, in: project)
                checking.removeAll()
            }
        }
        if chosen.contains(where: { $0.id == "hq" }) {
            let now = Date.now
            cache.observations["hq.app"] = .init(state: .healthy, observedAt: now, checkedAt: now, expiry: 120,
                                                reason: "This HQ process is active. Other applications remain independently unverified.",
                                                source: "Current HQ process", lastSuccess: now)
            do {
                _ = try store.context.fetchCount(FetchDescriptor<Project>())
                cache.observations["hq.storage"] = .init(state: .healthy, observedAt: now, checkedAt: now, expiry: 120,
                                                        reason: "SwiftData project query completed on this device.", source: "Local SwiftData read", lastSuccess: now)
            } catch {
                cache.observations["hq.storage"] = .init(state: .failed, observedAt: now, checkedAt: now, expiry: 120,
                                                        reason: "The local workspace query failed.", source: "Local SwiftData read", lastFailure: now)
            }
            let permission = await UNUserNotificationCenter.current().notificationSettings()
            let alerts = AlertPreferences.load()
            let notificationState: ConnectionState = !alerts.enabled ? .disabled :
                permission.authorizationStatus == .denied ? .degraded :
                permission.authorizationStatus == .notDetermined ? .missing : .unknown
            cache.observations["hq.notifications"] = .init(
                state: notificationState, observedAt: now, checkedAt: now, expiry: 120,
                reason: !alerts.enabled ? "HQ alerts are disabled in the existing alert preferences." :
                    permission.authorizationStatus == .denied ? "iOS notification permission is denied. Open HQ notification settings to review it." :
                    permission.authorizationStatus == .notDetermined ? "Notification permission has not been requested. Enable it through the existing HQ settings when desired." :
                    "Notification permission is available; actual scheduling and delivery remain unverified.",
                source: "Read-only local notification settings")
            if WCSession.isSupported() {
                let activated = WCSession.default.activationState == .activated
                let paired = WCSession.default.isPaired
                cache.observations["hq.watch"] = .init(state: !activated || paired ? .unknown : .missing,
                                                      observedAt: now, checkedAt: now, expiry: 120,
                                                      reason: !activated ? "WatchConnectivity is not yet activated; pairing and delivery are unverified." :
                                                        paired ? "A Watch is paired. Snapshot delivery and acknowledgement are not confirmed by pairing." :
                                                        "No paired Watch is reported by this phone's WatchConnectivity session.",
                                                      source: "Read-only WatchConnectivity state")
            }
            if let data = UserDefaults(suiteName: SharedStorage.group)?.data(forKey: SharedStorage.key),
               let shared = try? JSONDecoder().decode(DashboardSnapshot.self, from: data),
               shared.generatedAt <= now.addingTimeInterval(60), now.timeIntervalSince(shared.generatedAt) <= 120 {
                cache.observations["hq.storage-widgets"] = .init(state: .healthy, observedAt: shared.generatedAt, checkedAt: now, expiry: 120,
                                                               reason: "HQ read the shared snapshot. This does not verify WidgetKit rendered it.", source: "App Group snapshot read", lastSuccess: now)
            }
        }
        cache.lastRefresh = .now
        cache.activities = Array(cache.activities.sorted { $0.timestamp > $1.timestamp }.prefix(200))
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "Checks completed, but their local evidence cache could not be saved." }
    }
}
