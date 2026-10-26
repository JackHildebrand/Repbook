import Charts
import SwiftUI

struct ProgressionView: View {
    @EnvironmentObject private var store: WorkoutStore
    @State private var months = 2
    @State private var metric: ProgressMetric = .weight
    @State private var dataTools = false

    var body: some View {
        List {
            Section("Your progress") {
                HStack {
                    stat("Workouts", value: Double(store.data.workouts.count))
                    stat("Sets", value: Double(store.data.workouts.reduce(0) { $0 + $1.completedSets }))
                    stat("\(store.data.unit) volume", value: store.data.workouts.reduce(0) { $0 + $1.volume })
                }.padding(.vertical, 8)
            }
            Section {
                Picker("Date range", selection: $months) {
                    Text("Past month").tag(1)
                    Text("Past 2 months").tag(2)
                    Text("Past 3 months").tag(3)
                    Text("Past 6 months").tag(6)
                    Text("All time").tag(0)
                }
                Picker("Metric", selection: $metric) {
                    ForEach(ProgressMetric.allCases) { Text($0.rawValue).tag($0) }
                }
            } header: { Text("Exercise progress") } footer: {
                Text("Your six most-used exercises in this period. Tap or drag on a chart for details.")
            }
            let trends = store.data.progression(months: months == 0 ? nil : months, metric: metric)
            if trends.isEmpty {
                Section {
                    ContentUnavailableView("No workouts in this period", systemImage: "chart.xyaxis.line", description: Text("Choose a wider range, finish a workout, or import a Repbook backup in Settings."))
                }
            }
            ForEach(trends) { trend in
                Section {
                    ExerciseTrendCard(trend: trend, metric: metric, unit: store.data.unit)
                        .id("\(trend.id)-\(metric.id)-\(months)")
                }
            }
            Section("Records") {
                if store.data.weightRecords.isEmpty { Text("No records yet.").foregroundStyle(.secondary) }
                ForEach(store.data.weightRecords, id: \.exercise.id) { record in
                    HStack {
                        Text(record.exercise.name)
                        Spacer()
                        Text("\(record.weight.formatted()) \(store.data.unit)").fontWeight(.semibold).foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Progression")
        .toolbar { Button("Data", systemImage: "square.and.arrow.up") { dataTools = true } }
        .sheet(isPresented: $dataTools) { SettingsSheet() }
    }

    private func stat(_ title: String, value: Double) -> some View {
        VStack(spacing: 5) {
            Text(value.formatted(.number.precision(.fractionLength(0)))).font(.title3.bold()).minimumScaleFactor(0.5).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct ExerciseTrendCard: View {
    let trend: ExerciseProgress
    let metric: ProgressMetric
    let unit: String
    @State private var selectedDate: Date?
    private var selected: ProgressPoint? {
        guard let selectedDate else { return nil }
        return trend.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(trend.exercise.name).font(.headline)
                Spacer()
                Text("\(trend.uses) workouts").font(.caption).foregroundStyle(.secondary)
            }
            if let latest = trend.points.last {
                Text("Latest: \(latest.value.formatted()) · Best: \((trend.points.map(\.value).max() ?? 0).formatted()) \(metric.unit(unit))")
                    .font(.caption).foregroundStyle(.secondary)
                Chart {
                    ForEach(trend.points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                            .foregroundStyle(.blue)
                        PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                            .foregroundStyle(selected?.id == point.id ? Color.green : Color.blue)
                            .symbolSize(selected?.id == point.id ? 70 : 35)
                            .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityValue("\(point.value.formatted()) \(metric.unit(unit))")
                    }
                    if let selected {
                        RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(.secondary.opacity(0.3))
                    }
                }
                .chartYScale(domain: 0...max(1, (trend.points.map(\.value).max() ?? 1) * 1.1))
                .chartXSelection(value: $selectedDate)
                .frame(height: 175)
                if let selected {
                    Text("\(selected.date.formatted(date: .abbreviated, time: .shortened)): \(selected.value.formatted()) \(metric.unit(unit))")
                        .font(.caption).accessibilityAddTraits(.updatesFrequently)
                } else {
                    Text("Tap a point to see the date and value.").font(.caption).foregroundStyle(.secondary)
                }
                if trend.points.count == 1 {
                    Text("Log another workout to see a trend.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("No working sets logged yet.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}
