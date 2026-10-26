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
                }.foregroundStyle(.blue)
                HStack(alignment: .firstTextBaseline) {
                    Text(context.state.exercise).font(.headline).lineLimit(2)
                    Spacer()
                    Text(context.state.progress).font(.subheadline.bold()).foregroundStyle(.secondary)
                }
                if context.state.finished {
                    Text("All sets logged. Open Repbook to finish.").font(.caption)
                } else {
                    SetControls(context: context)
                }
                HStack {
                    Spacer()
                    if let end = context.state.restUntil {
                        Text("Rest")
                        Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true).monospacedDigit().frame(width: 55)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding().activityBackgroundTint(Color.black.opacity(0.9)).activitySystemActionForegroundColor(.blue)
                .widgetURL(URL(string: "repbook://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption).foregroundStyle(.blue) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.attributes.started, style: .timer).font(.caption).monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(context.state.exercise).font(.headline).lineLimit(1)
                            Spacer()
                            Text(context.state.progress).font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                        if !context.state.finished { SetControls(context: context) }
                        else { Text("Open Repbook to finish").font(.caption) }
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(.blue)
            } compactTrailing: {
                if let end = context.state.restUntil {
                    Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true).monospacedDigit().frame(width: 45)
                } else { Text(context.state.progress).font(.caption.bold()) }
            } minimal: { Image(systemName: "dumbbell.fill").foregroundStyle(.blue) }
            .widgetURL(URL(string: "repbook://workout"))
        }
    }
}

struct SetControls: View {
    let context: ActivityViewContext<WorkoutAttributes>
    private var state: WorkoutAttributes.ContentState { context.state }
    private var step: Double { state.unit == "kg" ? 2.5 : 5 }
    var body: some View {
        HStack(spacing: 8) {
            fastStepper(value: "\(state.weight.formatted()) \(state.unit)", minusWeight: -step, plusWeight: step)
            fastStepper(value: "\(state.reps) reps", minusReps: -1, plusReps: 1)
            Button(intent: LogSetIntent(sessionID: context.attributes.sessionID, setID: state.setID)) {
                Image(systemName: "checkmark").font(.headline).frame(width: 34, height: 38)
            }.buttonStyle(.borderedProminent).tint(.blue).accessibilityLabel("Log \(state.label)")
        }
    }
    private func fastStepper(value: String, minusWeight: Double = 0, plusWeight: Double = 0,
                             minusReps: Int = 0, plusReps: Int = 0) -> some View {
        HStack(spacing: 2) {
            adjust("−", weight: minusWeight, reps: minusReps)
            Text(value).font(.caption.bold()).monospacedDigit().frame(minWidth: 46)
            adjust("+", weight: plusWeight, reps: plusReps)
        }.frame(maxWidth: .infinity)
    }
    private func adjust(_ label: String, weight: Double = 0, reps: Int = 0) -> some View {
        Button(intent: AdjustSetIntent(sessionID: context.attributes.sessionID, setID: state.setID, weightDelta: weight, repDelta: reps)) {
            Text(label).font(.title3.bold()).frame(width: 32, height: 38)
        }.buttonStyle(.plain).contentShape(Rectangle()).tint(.blue)
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
                Image(systemName: "dumbbell.fill").font(.title).foregroundStyle(.blue)
                Text("Repbook").font(.headline)
                Text("Ready for your next set?").font(.caption).foregroundStyle(.secondary)
                Text("Open workout →").font(.caption.bold()).foregroundStyle(.blue)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(.black.gradient, for: .widget)
                .widgetURL(URL(string: "repbook://workout"))
        }.configurationDisplayName("Repbook").description("Open your routines or resume your workout.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
