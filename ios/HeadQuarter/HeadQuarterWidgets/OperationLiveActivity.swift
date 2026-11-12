import ActivityKit
import WidgetKit
import SwiftUI
struct OperationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OperationAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label(context.attributes.projectName, systemImage: "hammer"); Spacer(); Text(context.state.status).font(.caption.bold()) }
                Text(context.state.title).font(.headline)
                if let progress = context.state.progress { ProgressView(value: progress) }
                HStack {
                    Text(context.attributes.startedAt, style: .relative)
                    Spacer()
                    Text(context.attributes.deadline, style: .timer)
                }.font(.caption).foregroundStyle(.secondary)
                if context.isStale { Text("Time limit reached · open app to end").font(.caption).foregroundStyle(.orange) }
            }.padding().activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .widgetURL(URL(string: "headquarter://project/\(context.attributes.projectID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.projectName, systemImage: "hammer").font(.caption) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.isStale ? "Expired" : context.state.status).font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.headline)
                        if let progress = context.state.progress { ProgressView(value: progress) }
                        Text(context.attributes.deadline, style: .timer).font(.caption.monospacedDigit())
                    }
                }
            } compactLeading: { Image(systemName: context.isStale ? "clock.badge.exclamationmark" : "hammer.fill") }
              compactTrailing: {
                  if let progress = context.state.progress { Text(progress, format: .percent.precision(.fractionLength(0))).font(.caption2) }
                  else { Text(context.attributes.deadline, style: .timer).monospacedDigit().frame(maxWidth: 44) }
              } minimal: { Image(systemName: context.isStale ? "clock" : "hammer.fill") }
                .widgetURL(URL(string: "headquarter://project/\(context.attributes.projectID)"))
        }
    }
}
