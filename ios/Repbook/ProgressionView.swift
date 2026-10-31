import Charts
import SwiftUI

struct ProgressionView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var months = 3
    @State private var query = ""
    @State private var settings = false
    private var visible: [Session] {
        let cutoff = months == 0 ? Date.distantPast : Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .distantPast
        return store.data.workouts.filter { $0.started >= cutoff && $0.started <= .now }
    }
    private var trends: [ExerciseProgress] {
        store.data.progression(months: months == 0 ? nil : months, metric: .weight)
            .filter { query.isEmpty || $0.exercise.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PeriodPicker(months: $months)
                HStack(spacing: 12) {
                    SummaryTile(title: "Workouts", value: "\(visible.count)", icon: "calendar")
                    SummaryTile(title: "Volume PRs", value: "\(visible.flatMap(\.exercises).flatMap(\.sets).filter { $0.done && $0.volumePR == true }.count)", icon: "medal.fill")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Total training volume").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(visible.reduce(0) { $0 + $1.volume }.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit)")
                        .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(volumeTrend).font(.subheadline).foregroundStyle(volumeTrend.hasPrefix("+") && !volumeTrend.hasPrefix("+0.0%") ? Color.green : Color.secondary)
                }.repbookCard()
                NavigationLink { MuscleVolumeView() } label: {
                    HStack {
                        Label("Weekly hard sets", systemImage: "chart.bar.fill").font(.headline)
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.repbookCard()
                }.buttonStyle(.plain)
                Text("Exercise progression").font(.title3.weight(.semibold))
                if trends.isEmpty { ContentUnavailableView("No exercise history", systemImage: "chart.xyaxis.line", description: Text("Log a workout or choose a wider date range.")) }
                ForEach(trends) { trend in
                    NavigationLink { ExerciseProgressDetail(exercise: trend.exercise, months: months) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(trend.exercise.name).font(.headline)
                                Text("\(trend.uses) sessions").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let best = trend.points.map(\.value).max() {
                                Text("\(best.formatted()) \(store.data.unit)").font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.repbookCard()
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Color(uiColor: .systemBackground)).navigationTitle("Progress")
            .searchable(text: $query, prompt: "Search exercises")
            .toolbar { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
            .sheet(isPresented: $settings) { SettingsSheet() }
    }
    private var volumeTrend: String {
        guard months > 0, let start = Calendar.current.date(byAdding: .month, value: -months, to: .now),
              let previousStart = Calendar.current.date(byAdding: .month, value: -months, to: start) else { return "All recorded training" }
        let previous = store.data.workouts.filter { $0.started >= previousStart && $0.started < start }.reduce(0) { $0 + $1.volume }
        guard previous > 0 else { return "Not enough earlier data for a comparison" }
        let delta = (visible.reduce(0) { $0 + $1.volume } / previous - 1) * 100
        return "\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))% vs previous \(months) month\(months == 1 ? "" : "s")"
    }
}

struct PeriodPicker: View {
    @Binding var months: Int
    var body: some View {
        Picker("Date range", selection: $months) {
            Text("1M").tag(1); Text("3M").tag(3); Text("6M").tag(6); Text("1Y").tag(12); Text("All").tag(0)
        }.pickerStyle(.segmented).tint(.blue).frame(minHeight: 44)
    }
}

struct ExerciseProgressDetail: View {
    @EnvironmentObject private var store: WorkoutStore
    let exercise: Exercise
    @State var months = 3
    @State private var metric: ProgressMetric = .weight
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var haptics = true
    private var trend: ExerciseProgress? { store.data.progression(months: months == 0 ? nil : months, metric: metric).first { $0.id == exercise.id } }
    private var selected: ProgressPoint? {
        guard let selectedDate else { return nil }
        return trend?.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var sessions: [Session] {
        let ids = Set(trend?.points.map(\.id) ?? [])
        return store.data.workouts.filter { ids.contains($0.id) }.sorted { $0.started > $1.started }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseHeading(name: exercise.name)
                PeriodPicker(months: $months)
                Picker("Metric", selection: $metric) { ForEach(ProgressMetric.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.blue)
                if let trend, !trend.points.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selected == nil ? "Best \(metric.rawValue.lowercased())" : selected!.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\((selected?.value ?? trend.points.map(\.value).max() ?? 0).formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit(store.data.unit))")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit().contentTransition(.identity)
                        if let first = trend.points.first, let last = trend.points.last, trend.points.count > 1 {
                            let delta = last.value - first.value
                            Label("\(delta.formatted(.number.sign(strategy: .always()))) \(metric.unit(store.data.unit)) in selected period", systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.subheadline).foregroundStyle(delta >= 0 ? Color.green : Color.secondary)
                        }
                        Chart {
                            ForEach(trend.points) { point in
                                AreaMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.18), .blue.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
                                LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value)).foregroundStyle(.blue).interpolationMethod(.monotone)
                                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                    .foregroundStyle(Color.blue).symbolSize(point.id == selected?.id ? 65 : 25)
                                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue("\(point.value.formatted()) \(metric.unit(store.data.unit))")
                                if metric == .volume && isPR(point.id) {
                                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                        .symbol { Image(systemName: "medal.fill").font(.caption).foregroundStyle(.green) }
                                }
                            }
                            if let selected { RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(.secondary.opacity(0.4)) }
                        }.frame(height: 230).chartXSelection(value: $selectedDate)
                            .chartYScale(domain: chartRange(trend))
                        Text("Drag across the chart for exact values.").font(.caption).foregroundStyle(.secondary)
                        if metric == .volume { Text("Medals mark sessions containing a set-volume PR.").font(.caption).foregroundStyle(.secondary) }
                        if let first = trend.points.first, let last = trend.points.last, trend.points.count > 1 {
                            Text("\((last.value - first.value).formatted(.number.sign(strategy: .always()))) \(metric.unit(store.data.unit)) from first to latest session").font(.caption).foregroundStyle(.secondary)
                        }
                        if metric == .estimatedMax { Text("Estimated from working sets using the Epley formula. This is not a tested maximum.").font(.caption).foregroundStyle(.secondary) }
                    }.repbookCard()
                    HStack(spacing: 8) {
                        compactStat("Best set", bestSet)
                        compactStat("Est. 1RM", estimatedMax)
                        compactStat("Sessions", "\(sessions.count)")
                    }
                    Text("Sessions").font(.title3.weight(.semibold))
                    ForEach(sessions) { session in
                        NavigationLink { SessionDetailView(sessionID: session.id) } label: {
                            HStack { Text(session.started.formatted(date: .abbreviated, time: .omitted)); Spacer(); Image(systemName: "chevron.right").font(.caption) }.repbookCard()
                        }.buttonStyle(.plain)
                    }
                } else { ContentUnavailableView("No sets in this period", systemImage: "chart.xyaxis.line") }
            }.padding(20)
        }.background(Color(uiColor: .systemBackground)).navigationTitle("Exercise progression").navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: selected?.id) { _, _ in haptics }
            .onChange(of: months) { _, _ in selectedDate = nil }
            .onChange(of: metric) { _, _ in selectedDate = nil }
    }
    private func compactStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).minimumScaleFactor(0.65).lineLimit(1).monospacedDigit()
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private var estimatedMax: String {
        let sets = sessions.flatMap(\.exercises).filter { $0.exerciseID == exercise.id }.flatMap(\.sets).filter { $0.done && !$0.warmup }
        guard let best = sets.map({ $0.weight * (1 + Double($0.reps) / 30) }).max() else { return "—" }
        return "\(best.formatted(.number.precision(.fractionLength(0)))) \(store.data.unit)"
    }
    private func chartRange(_ trend: ExerciseProgress) -> ClosedRange<Double> {
        let maximum = trend.points.map(\.value).max() ?? 1
        let minimum = trend.points.map(\.value).min() ?? 0
        if metric == .weight || metric == .estimatedMax {
            let padding = max(1, (maximum - minimum) * 0.15)
            return max(0, minimum - padding)...max(1, maximum + padding)
        }
        return 0...max(1, maximum * 1.15)
    }
    private var bestSet: String {
        let sets = sessions.flatMap(\.exercises).filter { $0.exerciseID == exercise.id }.flatMap(\.sets).filter { $0.done && !$0.warmup }
        guard let set = sets.max(by: { $0.weight * Double($0.reps) < $1.weight * Double($1.reps) }) else { return "—" }
        return "\(set.weight.formatted()) × \(set.reps)"
    }
    private func isPR(_ sessionID: String) -> Bool {
        sessions.first { $0.id == sessionID }?.exercises.filter { $0.exerciseID == exercise.id }.flatMap(\.sets).contains { $0.volumePR == true } ?? false
    }
}

struct MuscleVolumeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var weekOffset = 0
    private var weekStart: Date {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        return cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7) + weekOffset * 7, to: today) ?? today
    }
    private func totals(start: Date) -> [String: Int] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        var result: [String: Int] = [:]
        for exercise in store.data.workouts.filter({ $0.started >= start && $0.started < end }).flatMap(\.exercises) {
            let group = store.data.exercises.first { $0.id == exercise.exerciseID }?.primaryMuscle ?? "Unassigned"
            result[group, default: 0] += exercise.sets.filter { $0.done && !$0.warmup }.count
        }
        return result
    }
    var body: some View {
        let current = totals(start: weekStart)
        let previous = totals(start: Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart)
        List {
            Section {
                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous week")
                    Spacer(); Text("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))").font(.headline); Spacer()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next week")
                }
            }
            if current.isEmpty { ContentUnavailableView("No working sets this week", systemImage: "chart.bar") }
            if !current.isEmpty {
                Section {
                    Chart(current.keys.sorted(), id: \.self) { group in
                        BarMark(x: .value("Hard sets", current[group] ?? 0), y: .value("Muscle", group)).foregroundStyle(.blue)
                    }.frame(height: CGFloat(max(1, current.count)) * 40)
                }
            }
            Section("Compared with previous week") {
                ForEach(Set(current.keys).union(previous.keys).sorted(), id: \.self) { group in
                    HStack {
                        Text(group); Spacer()
                        Text("\(current[group] ?? 0) sets").monospacedDigit()
                        Text("\((current[group, default: 0] - previous[group, default: 0]).formatted(.number.sign(strategy: .always())))").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Section {
                Text("Counts logged working sets for each exercise’s primary muscle. Warmups are excluded; effort is not measured. Edit muscle assignments from the exercise picker.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Weekly hard sets")
    }
}
