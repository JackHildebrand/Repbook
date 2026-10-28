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
                .font(.system(size: 17)).foregroundStyle(.secondary)
            Text(name.isEmpty ? "Rest day" : name)
                .font(.system(size: 23, weight: .bold)).foregroundStyle(.primary)
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
                Image(systemName: "dumbbell.fill").font(.title3).foregroundStyle(.primary)
                    .accessibilityLabel("Repbook")
            }
        }
        .padding(3)
        .containerBackground(Color(uiColor: .systemBackground), for: .widget)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Text(context.attributes.started, style: .timer).font(.caption).monospacedDigit()
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exercise).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                        Text("\(context.state.label) · \(context.state.progress)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if context.isRestComplete {
                        Label("Ready", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    } else if let end = context.state.restUntil {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("REST").font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true).font(.caption.weight(.semibold)).monospacedDigit().frame(width: 54)
                        }
                    }
                    if context.state.loggedPR == true { Image(systemName: "medal.fill").foregroundStyle(.green).accessibilityLabel("Volume PR logged") }
                }
                if context.state.finished { FinishWorkoutButton(sessionID: context.attributes.sessionID) }
                else { SetControls(context: context) }
            }.padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(.white)
                .activityBackgroundTint(Color.black.opacity(0.9)).activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "repbook://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !context.isRestComplete {
                        Label(context.attributes.name, systemImage: "dumbbell.fill").font(.caption).foregroundStyle(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isRestComplete { ActivityTopTimer(context: context) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.finished {
                        FinishWorkoutButton(sessionID: context.attributes.sessionID)
                    } else if context.isRestComplete {
                        RestCompleteMark(size: 44).frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(context.state.exercise).font(.headline).lineLimit(1)
                            Spacer()
                            Text(context.state.progress).font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                        if !context.state.finished {
                            Text("\(context.state.weight.formatted()) \(context.state.unit) × \(context.state.reps) reps").font(.subheadline).monospacedDigit()
                        } else { FinishWorkoutButton(sessionID: context.attributes.sessionID) }
                        if context.state.loggedPR == true { Label("Volume PR logged", systemImage: "medal.fill").font(.caption.bold()).foregroundStyle(.green) }
                    }
                    }
                }
            } compactLeading: {
                if context.isRestComplete {
                    RestCompleteMark(size: 26)
                } else if let end = context.state.restUntil {
                    IslandRestCountdown(started: context.attributes.started, end: end)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(.blue)
                }
            } compactTrailing: {
                // Keep the trailing region empty during rest so reduced-width presentations
                // devote the available space to a single complete m:ss countdown.
                if !context.isRestComplete && context.state.restUntil == nil {
                    Text(context.attributes.started, style: .timer).font(.caption).monospacedDigit().frame(width: 45)
                }
            } minimal: {
                if context.isRestComplete {
                    RestCompleteMark(size: 26)
                } else if let end = context.state.restUntil {
                    IslandRestCountdown(started: context.attributes.started, end: end)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(.blue)
                }
            }
            .widgetURL(URL(string: "repbook://workout"))
        }
    }
}

struct FinishWorkoutButton: View {
    let sessionID: String
    var body: some View {
        Button(intent: FinishWorkoutIntent(sessionID: sessionID)) {
            Label("Finish workout", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(.black).background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Save this completed workout and dismiss the Live Activity")
    }
}

struct RestCompleteMark: View {
    var size: CGFloat
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.green)
            .accessibilityLabel("Rest complete")
    }
}

struct IslandRestCountdown: View {
    let started: Date
    let end: Date
    var body: some View {
        // A system-driven countdown spans the original deadline, including full minutes.
        // No per-second app updates or separate 60-second phases are required.
        Text(timerInterval: min(started, end)...end, countsDown: true, showsHours: false)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit().multilineTextAlignment(.center)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: 36)
            .accessibilityLabel("Rest remaining")
    }
}

struct SetControls: View {
    let context: ActivityViewContext<WorkoutAttributes>
    private var state: WorkoutAttributes.ContentState { context.state }
    private var step: Double { state.unit == "kg" ? 2.5 : 5 }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                control("WEIGHT", value: "\(state.weight.formatted()) \(state.unit)", weight: step, reps: 0)
                control("REPS", value: "\(state.reps)", weight: 0, reps: 1)
            }
            Button(intent: LogSetIntent(sessionID: context.attributes.sessionID, setID: state.setID)) {
                Label("Log set", systemImage: "checkmark").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(.black).background(.white, in: Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Log \(state.label)")
        }
    }
    private func control(_ title: String, value: String, weight: Double, reps: Int) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                adjust("minus.circle", weight: -weight, reps: -reps, label: "Decrease " + title.lowercased())
                Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).contentTransition(.identity).animation(nil, value: value)
                adjust("plus.circle", weight: weight, reps: reps, label: "Increase " + title.lowercased())
            }
        }.padding(.horizontal, 4).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
    private func adjust(_ icon: String, weight: Double, reps: Int, label: String) -> some View {
        Button(intent: AdjustSetIntent(sessionID: context.attributes.sessionID, setID: state.setID, weightDelta: weight, repDelta: reps)) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 30, height: 30)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct ActivityTopTimer: View {
    let context: ActivityViewContext<WorkoutAttributes>
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text("Elapsed")
                Text(context.attributes.started, style: .timer)
                    .frame(width: 64, alignment: .trailing)
            }
            if context.isRestComplete {
                Label("Rest complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let end = context.state.restUntil {
                HStack(spacing: 4) {
                    Text("Rest")
                    Text(timerInterval: min(context.attributes.started, end)...end, countsDown: true)
                        .frame(width: 64, alignment: .trailing)
                }
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

private extension ActivityViewContext where Attributes == WorkoutAttributes {
    var isRestComplete: Bool {
        guard let deadline = state.restUntil else { return false }
        // staleDate is the rest deadline. iOS can invalidate this view without
        // waiting for the suspended app to send a new ContentState.
        return state.restComplete == true || isStale || deadline <= Date()
    }
}
