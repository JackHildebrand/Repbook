import Foundation

struct WeeklyMuscleActivity {
    let start: Date
    let end: Date
    let sets: [String: Int]
    var trainedGroups: [String] { Exercise.muscleGroups.filter { sets[$0, default: 0] > 0 } }
}

extension RepbookData {
    /// Today and the preceding six local calendar days. Only saved history is counted.
    func weeklyMuscleActivity(now: Date = .now, calendar: Calendar = .current) -> WeeklyMuscleActivity {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let muscles = Dictionary(exercises.map { ($0.id, $0.primaryMuscle) }, uniquingKeysWith: { first, _ in first })
        var totals: [String: Int] = [:]
        for workout in workouts where workout.started >= start && workout.started <= now {
            for exercise in workout.exercises {
                let count = exercise.sets.filter { $0.done && !$0.warmup }.count
                if count > 0 { totals[muscles[exercise.exerciseID] ?? "Unassigned", default: 0] += count }
            }
        }
        return WeeklyMuscleActivity(start: start, end: now, sets: totals)
    }
}
