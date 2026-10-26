import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RepbookWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity(); RoutineLauncher() }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption.bold())
                    Spacer()
                    Text(context.attributes.started, style: .timer).monospacedDigit().font(.caption)
                }.foregroundStyle(.orange)
                Text(context.state.exercise).font(.headline).lineLimit(2)
                if context.state.finished {
                    Text("All sets logged. Open Repbook to finish.").font(.caption)
                } else {
                    SetControls(context: context)
                }
                HStack {
                    Text("\(context.state.completed) sets logged")
                    Spacer()
                    if let end = context.state.restUntil {
                        Text("Rest")
                        Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true).monospacedDigit().frame(width: 55)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding().activityBackgroundTint(Color.black.opacity(0.9)).activitySystemActionForegroundColor(.orange)
                .widgetURL(URL(string: "repbook://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption).foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.started, style: .timer).font(.caption).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.exercise).font(.headline).lineLimit(1)
                        if !context.state.finished { SetControls(context: context) }
                        else { Text("Open Repbook to finish").font(.caption) }
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
            } compactTrailing: {
                if let end = context.state.restUntil {
                    Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true).monospacedDigit().frame(width: 45)
                } else { Text("\(context.state.completed)✓").font(.caption) }
            } minimal: { Image(systemName: "dumbbell.fill").foregroundStyle(.orange) }
            .widgetURL(URL(string: "repbook://workout"))
        }
    }
}

struct SetControls: View {
    let context: ActivityViewContext<WorkoutAttributes>
    private var state: WorkoutAttributes.ContentState { context.state }
    private var step: Double { state.unit == "kg" ? 2.5 : 5 }
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("\(state.weight.formatted()) \(state.unit)").font(.subheadline.bold()).monospacedDigit()
                HStack {
                    adjust("−", weight: -step).accessibilityLabel("Decrease weight by \(step.formatted()) \(state.unit)")
                    adjust("+", weight: step).accessibilityLabel("Increase weight by \(step.formatted()) \(state.unit)")
                }
            }.frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                Text("\(state.reps) reps").font(.subheadline.bold()).monospacedDigit()
                HStack {
                    adjust("−", reps: -1).accessibilityLabel("Decrease reps")
                    adjust("+", reps: 1).accessibilityLabel("Increase reps")
                }
            }.frame(maxWidth: .infinity)
            Button(intent: LogSetIntent(sessionID: context.attributes.sessionID, setID: state.setID)) {
                Label("Log", systemImage: "checkmark").font(.headline).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(.orange).accessibilityLabel("Log \(state.label)")
        }
    }
    private func adjust(_ label: String, weight: Double = 0, reps: Int = 0) -> some View {
        Button(intent: AdjustSetIntent(sessionID: context.attributes.sessionID, setID: state.setID, weightDelta: weight, repDelta: reps)) {
            Text(label).font(.headline).frame(minWidth: 28, minHeight: 28)
        }.buttonStyle(.bordered).tint(.orange)
    }
}

struct LauncherEntry: TimelineEntry { var date: Date }
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry { LauncherEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) { completion(LauncherEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}
struct RoutineLauncher: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RepbookLauncher", provider: LauncherProvider()) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "dumbbell.fill").font(.title).foregroundStyle(.orange)
                Text("Repbook").font(.headline)
                Text("Ready for your next set?").font(.caption).foregroundStyle(.secondary)
                Text("Open workout →").font(.caption.bold()).foregroundStyle(.orange)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(.black.gradient, for: .widget)
                .widgetURL(URL(string: "repbook://workout"))
        }.configurationDisplayName("Repbook").description("Open your routines or resume your workout.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
