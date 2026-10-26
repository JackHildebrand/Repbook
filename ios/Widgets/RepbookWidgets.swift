import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RepbookWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        ScheduledRoutineWidget()
        ScheduledRoutineLockScreenWidget()
        RoutineLauncher()
    }
}

struct ScheduledRoutineEntry: TimelineEntry {
    let date: Date
    let configuration: WeeklyRoutineConfiguration
}

struct ScheduledRoutineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScheduledRoutineEntry {
        ScheduledRoutineEntry(date: .now, configuration: WeeklyRoutineConfiguration())
    }
    func snapshot(for configuration: WeeklyRoutineConfiguration, in context: Context) async -> ScheduledRoutineEntry {
        ScheduledRoutineEntry(date: .now, configuration: configuration)
    }
    func timeline(for configuration: WeeklyRoutineConfiguration, in context: Context) async -> Timeline<ScheduledRoutineEntry> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let entries = (0..<8).compactMap { offset -> ScheduledRoutineEntry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ScheduledRoutineEntry(date: date, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct ScheduledRoutineWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RepbookScheduledRoutine", intent: WeeklyRoutineConfiguration.self, provider: ScheduledRoutineProvider()) { entry in
            ScheduledRoutineView(entry: entry)
        }
        .configurationDisplayName("Scheduled workout")
        .description("Set a routine for each day. Tap the arrow to start today's workout and Live Activity in the background.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScheduledRoutineView: View {
    let entry: ScheduledRoutineEntry
    private var name: String { entry.configuration.routine(on: entry.date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.date.formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 17)).foregroundStyle(Color.gray)
            Text(name.isEmpty ? "Rest day" : name)
                .font(.system(size: 23, weight: .bold)).foregroundStyle(Color.black)
                .lineLimit(2).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(alignment: .bottom) {
                if !name.isEmpty {
                    Button(intent: StartScheduledWorkoutIntent(schedule: entry.configuration.encodedSchedule)) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.blue, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Start \(name)")
                } else {
                    Image(systemName: "moon.zzz").font(.title2).foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "dumbbell.fill").font(.title3).foregroundStyle(.black)
                    .accessibilityLabel("Repbook")
            }
        }
        .padding(3)
        .containerBackground(.white, for: .widget)
    }
}

struct ScheduledRoutineLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "RepbookScheduledRoutineLockScreen",
            intent: WeeklyRoutineConfiguration.self,
            provider: ScheduledRoutineProvider()
        ) { entry in
            ScheduledRoutineLockScreenView(entry: entry)
        }
        .configurationDisplayName("Scheduled workout — Lock Screen")
        .description("Tap the barbell to start today's scheduled routine and Live Activity.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ScheduledRoutineLockScreenView: View {
    let entry: ScheduledRoutineEntry
    private var name: String { entry.configuration.routine(on: entry.date) }

    var body: some View {
        Button(intent: StartScheduledWorkoutIntent(schedule: entry.configuration.encodedSchedule)) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(name.isEmpty ? "Rest day" : "Start \(name)")
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption.bold())
                    Spacer()
                    ActivityTopTimer(context: context)
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
                if context.state.loggedPR == true {
                    Text("🏅 PR logged").font(.caption.bold()).foregroundStyle(.blue)
                }
            }.padding().activityBackgroundTint(Color.black.opacity(0.9)).activitySystemActionForegroundColor(.blue)
                .widgetURL(URL(string: "repbook://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption).foregroundStyle(.blue) }
                DynamicIslandExpandedRegion(.trailing) { ActivityTopTimer(context: context) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(context.state.exercise).font(.headline).lineLimit(1)
                            Spacer()
                            Text(context.state.progress).font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                        if !context.state.finished { SetControls(context: context) }
                        else { Text("Open Repbook to finish").font(.caption) }
                        if context.state.loggedPR == true { Text("🏅 PR logged").font(.caption.bold()).foregroundStyle(.blue) }
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
                .contentTransition(.identity)
                .animation(.easeOut(duration: 0.1), value: value)
            adjust("+", weight: plusWeight, reps: plusReps)
        }.frame(maxWidth: .infinity)
    }
    private func adjust(_ label: String, weight: Double = 0, reps: Int = 0) -> some View {
        Button(intent: AdjustSetIntent(sessionID: context.attributes.sessionID, setID: state.setID, weightDelta: weight, repDelta: reps)) {
            Text(label).font(.title3.bold()).frame(width: 32, height: 38)
        }.buttonStyle(.plain).contentShape(Rectangle()).tint(.blue)
    }
}

struct ActivityTopTimer: View {
    let context: ActivityViewContext<WorkoutAttributes>
    var body: some View {
        HStack(spacing: 4) {
            if let end = context.state.restUntil {
                Text("Rest")
                Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true)
                    .frame(width: 48)
            } else {
                Text(context.attributes.started, style: .timer)
            }
        }.font(.caption).monospacedDigit()
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
