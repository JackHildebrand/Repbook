import Foundation

enum ProgressMetric: String, CaseIterable, Identifiable {
    case weight = "Top weight", estimatedMax = "Est. 1RM", reps = "Total reps", volume = "Volume"
    var id: String { rawValue }
    func unit(_ unit: String) -> String { self == .reps ? "reps" : self == .volume ? "\(unit) volume" : unit }
}

struct ProgressPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

struct ExerciseProgress: Identifiable {
    let exercise: Exercise
    let uses: Int
    let points: [ProgressPoint]
    var id: String { exercise.id }
}

extension RepbookData {
    func progression(months: Int?, metric: ProgressMetric, now: Date = Date(), calendar: Calendar = .current) -> [ExerciseProgress] {
        let cutoff = months.flatMap { calendar.date(byAdding: .month, value: -$0, to: calendar.startOfDay(for: now)) }
        let visible = workouts.filter { $0.started <= now && (cutoff == nil || $0.started >= cutoff!) }
        return exercises.compactMap { exercise -> ExerciseProgress? in
            let sessions = visible.filter { $0.exercises.contains { $0.exerciseID == exercise.id } }
            guard !sessions.isEmpty else { return nil }
            let points = sessions.compactMap { session -> ProgressPoint? in
                let sets = session.exercises.filter { $0.exerciseID == exercise.id }.flatMap(\.sets)
                    .filter { $0.done && !$0.warmup && $0.reps > 0 && $0.weight.isFinite && $0.weight >= 0 }
                guard !sets.isEmpty else { return nil }
                let value: Double
                switch metric {
                case .estimatedMax: value = sets.map { $0.weight * (1 + Double($0.reps) / 30) }.max() ?? 0
                case .weight: value = sets.map(\.weight).max() ?? 0
                case .reps: value = sets.reduce(0) { $0 + Double($1.reps) }
                case .volume: value = sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
                }
                return ProgressPoint(id: session.id, date: session.started, value: value)
            }.sorted { $0.date < $1.date }
            return ExerciseProgress(exercise: exercise, uses: sessions.count, points: points)
        }.sorted {
            $0.uses == $1.uses ? $0.exercise.name.localizedStandardCompare($1.exercise.name) == .orderedAscending : $0.uses > $1.uses
        }
    }

    var weightRecords: [(exercise: Exercise, weight: Double)] {
        exercises.compactMap { exercise -> (exercise: Exercise, weight: Double)? in
            let sets = workouts.flatMap(\.exercises).filter { $0.exerciseID == exercise.id }.flatMap(\.sets)
                .filter { $0.done && !$0.warmup }
            guard let best = sets.map(\.weight).max(), best > 0 else { return nil }
            return (exercise, best)
        }.sorted { $0.weight > $1.weight }
    }
}
