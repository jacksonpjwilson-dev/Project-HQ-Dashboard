import WidgetKit
import SwiftUI
import AppIntents

struct WidgetProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = WidgetProjectQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct WidgetProjectQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetProjectEntity] {
        SharedStorage.load().projects.filter { identifiers.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [WidgetProjectEntity] {
        SharedStorage.load().projects.map { .init(id: $0.id, name: $0.name) }
    }
}
struct DashboardConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Command centre"
    static var description = IntentDescription("Select projects for your dashboard. Leave empty to use dashboard order.")
    @Parameter(title: "Projects") var projects: [WidgetProjectEntity]?
}
struct DashboardEntry: TimelineEntry {
    var date: Date
    var snapshot: DashboardSnapshot
    var selected: [UUID]
    var projects: [ProjectSnapshot] {
        selected.isEmpty ? snapshot.projects : selected.compactMap { id in snapshot.projects.first { $0.id == id } }
    }
    var health: Health {
        let states = snapshot.projects.map { $0.currentHealth(at: date) }
        if let failure = states.filter({ $0.severity >= 2 }).max(by: { $0.severity < $1.severity }) { return failure }
        return !states.isEmpty && states.allSatisfy { $0 == .healthy } ? .healthy : .unknown
    }
    var alerts: Int { snapshot.projects.reduce(0) { $0 + $1.alerts } }
}
struct DashboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry { .init(date: .now, snapshot: .empty, selected: []) }
    func snapshot(for configuration: DashboardConfiguration, in context: Context) async -> DashboardEntry {
        .init(date: .now, snapshot: SharedStorage.load(), selected: configuration.projects?.map(\.id) ?? [])
    }
    func timeline(for configuration: DashboardConfiguration, in context: Context) async -> Timeline<DashboardEntry> {
        let snapshot = SharedStorage.load(), now = Date.now
        let expirations = snapshot.projects.compactMap(\.validUntil).filter { $0 > now && $0 < now.addingTimeInterval(4 * 3600) }.map { $0.addingTimeInterval(1) }
        let dates = [now] + Array(Set(expirations)).sorted()
        let entries = dates.map { DashboardEntry(date: $0, snapshot: snapshot, selected: configuration.projects?.map(\.id) ?? []) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }
}
extension Health {
    var widgetColor: Color {
        switch self { case .healthy: return .green; case .needsHelp: return .yellow; case .error: return .orange; case .down: return .red; case .unknown: return .secondary }
    }
}
struct DashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DashboardEntry
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("HQ · \(entry.health.label) · \(entry.alerts) alerts")
            case .accessoryCircular:
                Gauge(value: entry.snapshot.overallProgress) { Image(systemName: entry.health.symbol) } currentValueLabel: { Text(entry.snapshot.overallProgress, format: .percent.precision(.fractionLength(0))) }.gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading) { Label("Head Quarter", systemImage: entry.health.symbol).font(.headline); Text("\(entry.alerts) alerts · \(entry.snapshot.overallProgress.formatted(.percent.precision(.fractionLength(0)))) complete").font(.caption) }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEAD QUARTER").font(.caption2.bold()).foregroundStyle(.secondary)
                    Image(systemName: entry.health.symbol).font(.largeTitle).foregroundStyle(entry.health.widgetColor)
                    Text(entry.health.label).font(.headline)
                    Text("\(entry.alerts) active alerts").font(.caption).foregroundStyle(.secondary)
                    if entry.snapshot.projects.isEmpty { Text("Open app to configure").font(.caption2) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 6) {
                    HStack { Label("Head Quarter", systemImage: "building.2").font(.headline); Spacer(); Text("\(entry.alerts) alerts").font(.caption).foregroundStyle(entry.alerts > 0 ? .orange : .secondary) }
                    if entry.projects.isEmpty { Text("Open the app to share your project dashboard.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(entry.projects.prefix(family == .systemLarge ? 6 : 2))) { project in
                        Link(destination: URL(string: "headquarter://project/\(project.id)")!) {
                            VStack(spacing: 4) {
                                HStack { Image(systemName: project.currentHealth(at: entry.date).symbol).foregroundStyle(project.currentHealth(at: entry.date).widgetColor); Text(project.name).font(.subheadline).lineLimit(1); Spacer(); Text(project.progress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()) }
                                ProgressView(value: project.progress).tint(.indigo)
                            }
                        }
                    }
                    if family == .systemLarge {
                        Spacer(minLength: 0)
                        Text("Snapshot \(entry.snapshot.generatedAt.formatted(date: .omitted, time: .shortened)) · stale checks become unknown").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "headquarter://help"))
        .accessibilityLabel("Head Quarter, \(entry.health.label), \(entry.alerts) active alerts")
    }
}
struct HeadQuarterDashboardWidget: Widget {
    let kind = "HeadQuarterDashboard"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DashboardConfiguration.self, provider: DashboardProvider()) { DashboardWidgetView(entry: $0) }
            .configurationDisplayName("Head Quarter")
            .description("Development progress and evidence-based operational health.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
@main struct HeadQuarterWidgetBundle: WidgetBundle {
    var body: some Widget { HeadQuarterDashboardWidget(); OperationLiveActivity() }
}
