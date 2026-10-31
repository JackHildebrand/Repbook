import SwiftUI

struct WorkoutHome: View {
    @EnvironmentObject private var store: WorkoutStore
    var onStart: () -> Void
    @State private var settings = false
    @State private var schedule = false
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var weekOffset = 0
    @State private var editor: Routine?
    private var assigned: Routine? { store.data.scheduledRoutine(on: selectedDay) }
    private var selectedIsToday: Bool { Calendar.current.isDateInToday(selectedDay) }
    private var monthWorkouts: [Session] {
        store.data.workouts.filter { Calendar.current.isDate($0.started, equalTo: .now, toGranularity: .month) }
    }
    private var volumeTrend: String {
        let cal = Calendar.current
        guard let current = cal.dateInterval(of: .month, for: .now),
              let previousDate = cal.date(byAdding: .month, value: -1, to: .now),
              let previous = cal.dateInterval(of: .month, for: previousDate) else { return "—" }
        // Compare equal elapsed portions of each month, not a partial month against a full month.
        let elapsed = Date.now.timeIntervalSince(current.start)
        let end = min(previous.end, previous.start.addingTimeInterval(elapsed))
        let old = store.data.workouts.filter { $0.started >= previous.start && $0.started < end }.reduce(0) { $0 + $1.volume }
        let new = monthWorkouts.reduce(0) { $0 + $1.volume }
        guard old > 0 else { return "—" }
        let change = (new / old - 1) * 100
        return "\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1))))%"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.data.active != nil ? "IN PROGRESS" : "SCHEDULED WORKOUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let active = store.data.active {
                        Text(active.name).font(.largeTitle.weight(.semibold))
                        Text("\(active.completedSets) sets logged").foregroundStyle(.secondary)
                        Button { onStart() } label: { Label("Resume workout", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(RepbookPrimaryStyle())
                    } else if let routine = assigned {
                        Text(routine.name).font(.largeTitle.weight(.semibold))
                        Text("\(routine.exercises.count) exercises · \(routine.exercises.reduce(0) { $0 + $1.sets.count }) working sets")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { store.start(routine); if store.data.active != nil { onStart() } } label: {
                            Label("Start workout", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(RepbookPrimaryStyle())
                    } else {
                        Text("Rest day").font(.largeTitle.weight(.semibold))
                        Text("Choose a routine when you’re ready to train.").foregroundStyle(.secondary)
                        Button("Choose routine") { schedule = true }.frame(maxWidth: .infinity).buttonStyle(RepbookPrimaryStyle())
                    }
                    Button("Change routine") { schedule = true }.font(.subheadline).frame(minHeight: 44)
                }.repbookCard()
                    .contextMenu {
                        Button("Change scheduled routine", systemImage: "calendar") { schedule = true }
                        if let assigned { Button("Edit routine", systemImage: "pencil") { editor = assigned } }
                    }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(weekOffset == 0 ? "This week" : weekLabel).font(.title3.weight(.semibold))
                        Spacer()
                        Button { moveWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous week")
                        Button { moveWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next week")
                        Button("Edit") { schedule = true }.frame(minHeight: 44)
                    }
                    HStack(spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            Button { selectedDay = day } label: {
                                VStack(spacing: 8) {
                                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption)
                                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                                    let completed = store.data.workouts.contains { Calendar.current.isDate($0.started, inSameDayAs: day) }
                                    Image(systemName: completed ? "checkmark" : (store.data.scheduledRoutine(on: day) != nil ? "dumbbell.fill" : "circle"))
                                        .font(.subheadline).frame(width: 38, height: 38)
                                        .foregroundStyle(isSelected ? Color.white : (completed ? Color.green : Color.primary))
                                        .background(isSelected ? Color.blue : Color(uiColor: .tertiarySystemFill), in: Circle())
                                }.frame(maxWidth: .infinity, minHeight: 72)

                            }.buttonStyle(.plain).accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(store.data.scheduledRoutine(on: day)?.name ?? "Rest day")")
                                .contextMenu { Button("Assign routine") { selectedDay = day; schedule = true } }
                        }
                    }.gesture(DragGesture(minimumDistance: 40).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        moveWeek(value.translation.width < 0 ? 1 : -1)
                    })
                }
                HStack(spacing: 12) {
                    NavigationLink { ProgressionView() } label: { SummaryTile(title: "Workouts this month", value: "\(monthWorkouts.count)", icon: "calendar") }
                    NavigationLink { ProgressionView() } label: { SummaryTile(title: "Volume trend", value: volumeTrend, icon: "chart.line.uptrend.xyaxis", valueColor: volumeTrend.hasPrefix("+") && volumeTrend != "+0.0%" ? .green : .primary) }
                }.buttonStyle(.plain)
                if let last = store.data.workouts.max(by: { $0.started < $1.started }) {
                    NavigationLink { SessionDetailView(sessionID: last.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent activity").font(.title3.weight(.semibold))
                            Text(last.name).font(.headline)
                            Text(last.started.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                            Text("\(last.completedSets) sets · \(last.volume.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit)").font(.subheadline)
                        }.repbookCard()
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Color(uiColor: .systemBackground)).navigationTitle(selectedIsToday ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide)))
            .toolbar { Button { settings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.accessibilityLabel("Settings") }
            .sheet(isPresented: $settings) { SettingsSheet() }
            .sheet(isPresented: $schedule) { ScheduleSheet(selectedDay: Calendar.current.component(.weekday, from: selectedDay)) }
            .sheet(item: $editor) { RoutineEditor(draft: $0) }
    }
    private var weekDays: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let mondayOffset = (cal.component(.weekday, from: start) + 5) % 7
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0 - mondayOffset + weekOffset * 7, to: start) }
    }
    private var weekLabel: String { weekDays.first?.formatted(.dateTime.month(.abbreviated).day()) ?? "Week" }
    private func moveWeek(_ delta: Int) { weekOffset += delta; if let day = weekDays.first { selectedDay = day } }
}

struct ScheduleSheet: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var selectedDay: Int = 2
    private let days = [(2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday"), (1, "Sunday")]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(days, id: \.0) { day, name in
                        Picker(name, selection: Binding(get: { store.data.weekdayRoutines?[String(day)] ?? "" }, set: { id in
                            store.change {
                                if $0.weekdayRoutines == nil { $0.weekdayRoutines = [:] }
                                $0.weekdayRoutines?[String(day)] = id.isEmpty ? nil : id
                            }
                        })) {
                            Text("Rest day").tag("")
                            ForEach(store.data.routines) { Text($0.name).tag($0.id) }
                        }.tint(day == selectedDay ? .blue : .primary)
                    }
                } footer: { Text("This weekly schedule repeats. Widgets use today’s routine from this schedule first. On days without an assignment here, they use the routine set in Edit Widget.") }
            }.navigationTitle("Weekly schedule").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.presentationDetents([.large])
    }
}
