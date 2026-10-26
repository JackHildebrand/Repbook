import Foundation

struct Exercise: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
}

struct WorkoutSet: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var weight: Double = 0
    var reps: Int = 8
    var warmup = false
    var done = false
    var weightPR: Bool?
    var volumePR: Bool?
}

struct RoutineExercise: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var exerciseID: String
    var warmupCount = 2
    var sets = [WorkoutSet()]
}

struct Routine: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var exercises: [RoutineExercise] = []
}

struct SessionExercise: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var exerciseID: String
    var sets: [WorkoutSet]
}

struct Session: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var started = Date()
    var ended: Date?
    var exercises: [SessionExercise]
    var restUntil: Date?
    var completedSets: Int { exercises.flatMap(\.sets).filter(\.done).count }
    var volume: Double { exercises.flatMap(\.sets).filter { $0.done && !$0.warmup }.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var nextSet: (exercise: Int, set: Int)? {
        for (ei, exercise) in exercises.enumerated() {
            if let si = exercise.sets.firstIndex(where: { !$0.done }) { return (ei, si) }
        }
        return nil
    }
}

struct RepbookData: Codable, Equatable {
    var schemaVersion = 1
    var unit = "lbs"
    var restSeconds = 120
    var exercises: [Exercise]
    var routines: [Routine]
    var workouts: [Session] = []
    var active: Session?

    static func seed() -> Self {
        let names = ["Bench Press (Barbell)", "Chest Press (Machine)", "Chest Fly (Machine)", "Shoulder Press (Machine)", "Lateral Raise (Machine)", "Lat Pulldown (Cable)", "Seated Row (Machine)", "Wide Grip Seated Row (Machine)", "Neutral Grip Seated Row (Machine)", "Preacher Curl (Machine)", "Bicep Curl (Dumbbell)", "Triceps Pushdown (Cable)", "Squat (Barbell)", "Leg Press (Machine)", "Leg Extension (Machine)", "Seated Leg Curl (Machine)", "Romanian Deadlift (Barbell)", "Calf Extension (Machine)", "Crunch (Machine)", "Back Extension (Machine)", "Hip Adduction (Machine)", "Hip Abduction (Machine)"]
        let exercises = names.map { Exercise(name: $0) }
        func routine(_ name: String, _ names: [String]) -> Routine {
            Routine(name: name, exercises: names.compactMap { name in
                exercises.first(where: { $0.name == name }).map { RoutineExercise(exerciseID: $0.id) }
            })
        }
        return Self(exercises: exercises, routines: [
            routine("Upper", ["Chest Press (Machine)", "Lat Pulldown (Cable)", "Chest Fly (Machine)", "Seated Row (Machine)", "Lateral Raise (Machine)", "Preacher Curl (Machine)", "Triceps Pushdown (Cable)"]),
            routine("Lower", ["Leg Extension (Machine)", "Seated Leg Curl (Machine)", "Leg Press (Machine)", "Calf Extension (Machine)", "Crunch (Machine)"])
        ])
    }

    func starting(_ routine: Routine) -> Session {
        Session(name: routine.name, exercises: routine.exercises.map { item in
            let previous = workouts.sorted { $0.started > $1.started }
                .compactMap { $0.exercises.first(where: { $0.exerciseID == item.exerciseID }) }
                .first?.sets.filter { !$0.warmup && $0.done } ?? []
            let working = item.sets.enumerated().map { index, template in
                WorkoutSet(weight: previous.indices.contains(index) ? previous[index].weight : template.weight,
                           reps: previous.indices.contains(index) ? previous[index].reps : template.reps)
            }
            let base = working.first?.weight ?? 0
            let step = unit == "kg" ? 2.5 : 5.0
            let plan: [(Double, Int)] = item.warmupCount == 1 ? [(0.65, 6)] : item.warmupCount == 2 ? [(0.5, 8), (0.75, 4)] : []
            let warmups = plan.map { ratio, reps in
                WorkoutSet(weight: min(base, (base * ratio / step).rounded() * step), reps: reps, warmup: true)
            }
            return SessionExercise(exerciseID: item.exerciseID, sets: warmups + working)
        })
    }

    mutating func convertUnit(to newUnit: String) {
        guard newUnit != unit, ["lbs", "kg"].contains(newUnit) else { return }
        let factor = newUnit == "kg" ? 1 / 2.2046226218 : 2.2046226218
        func converted(_ set: WorkoutSet) -> WorkoutSet {
            var value = set; value.weight = (set.weight * factor * 100).rounded() / 100; return value
        }
        for ri in routines.indices { for ei in routines[ri].exercises.indices {
            routines[ri].exercises[ei].sets = routines[ri].exercises[ei].sets.map(converted)
        } }
        for wi in workouts.indices { for ei in workouts[wi].exercises.indices {
            workouts[wi].exercises[ei].sets = workouts[wi].exercises[ei].sets.map(converted)
        } }
        if var session = active {
            for ei in session.exercises.indices { session.exercises[ei].sets = session.exercises[ei].sets.map(converted) }
            active = session
        }
        unit = newUnit
    }

    func validate() throws {
        guard schemaVersion == 1, ["lbs", "kg"].contains(unit), (0...1800).contains(restSeconds),
              Set(exercises.map(\.id)).count == exercises.count,
              Set(routines.map(\.id)).count == routines.count,
              Set(workouts.map(\.id)).count == workouts.count else { throw BackupError.invalid }
        let ids = Set(exercises.map(\.id))
        func valid(_ sets: [WorkoutSet]) -> Bool {
            Set(sets.map(\.id)).count == sets.count && sets.allSatisfy { $0.weight.isFinite && $0.weight >= 0 && (1...999).contains($0.reps) }
        }
        guard routines.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.exercises.isEmpty &&
            Set($0.exercises.map(\.id)).count == $0.exercises.count && $0.exercises.allSatisfy { ids.contains($0.exerciseID) && (0...2).contains($0.warmupCount) && !$0.sets.isEmpty && valid($0.sets) }
        }) else { throw BackupError.invalid }
        for session in workouts + (active.map { [$0] } ?? []) {
            guard session.started.timeIntervalSince1970.isFinite,
                  session.ended.map({ $0 >= session.started }) ?? true,
                  Set(session.exercises.map(\.id)).count == session.exercises.count,
                  session.exercises.allSatisfy({ ids.contains($0.exerciseID) && valid($0.sets) }) else { throw BackupError.invalid }
        }
    }
}

enum BackupError: LocalizedError {
    case invalid
    var errorDescription: String? { "This file is not a valid Repbook backup. Your current data has not been changed." }
}

enum BackupImporter {
    static func decode(_ bytes: Data) throws -> RepbookData {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let native = try? decoder.decode(RepbookData.self, from: bytes) { try native.validate(); return native }
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let catalog = root["exercises"] as? [[String: Any]],
              let routines = root["routines"] as? [[String: Any]],
              let workouts = root["workouts"] as? [[String: Any]] else { throw BackupError.invalid }
        func number(_ value: Any?) -> Double { Double(String(describing: value ?? "")) ?? 0 }
        func date(_ value: Any?) throws -> Date {
            guard let value = value as? String else { throw BackupError.invalid }
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { throw BackupError.invalid }
            return date
        }
        func set(_ raw: [String: Any], template: Bool = false) -> WorkoutSet {
            let weightText = String(describing: raw["weight"] ?? "")
            let repText = String(describing: raw["reps"] ?? "")
            return WorkoutSet(weight: number(weightText.isEmpty ? raw["previousWeight"] : raw["weight"]),
                              reps: max(1, Int(number(repText.isEmpty ? raw["previousReps"] : raw["reps"]))),
                              warmup: (raw["type"] as? String ?? raw["set_type"] as? String) == "warmup",
                              done: !template && (raw["done"] as? Bool ?? false),
                              weightPR: raw["pr"] as? Bool,
                              volumePR: raw["volumePR"] as? Bool)
        }
        func session(_ raw: [String: Any]) throws -> Session {
            guard let name = raw["name"] as? String, let entries = raw["exercises"] as? [[String: Any]] else { throw BackupError.invalid }
            let exercises = try entries.map { item -> SessionExercise in
                guard let id = item["exerciseId"] as? String, let sets = item["sets"] as? [[String: Any]] else { throw BackupError.invalid }
                return SessionExercise(exerciseID: id, sets: sets.map { set($0) })
            }
            let ended: Date?
            if let value = raw["end"], !(value is NSNull) { ended = try date(value) } else { ended = nil }
            return Session(id: raw["id"] as? String ?? UUID().uuidString, name: name,
                           started: try date(raw["start"]), ended: ended, exercises: exercises)
        }
        let exercises = try catalog.map { raw -> Exercise in
            guard let id = raw["id"] as? String, let name = raw["name"] as? String else { throw BackupError.invalid }
            return Exercise(id: id, name: name)
        }
        let warmupCounts = root["warmupCounts"] as? [String: Int] ?? [:]
        let converted = try routines.map { raw -> Routine in
            guard let name = raw["name"] as? String, let ids = raw["exerciseIds"] as? [String] else { throw BackupError.invalid }
            let templates = raw["templates"] as? [String: [[String: Any]]] ?? [:]
            return Routine(id: raw["id"] as? String ?? UUID().uuidString, name: name, exercises: ids.map {
                RoutineExercise(exerciseID: $0, warmupCount: warmupCounts[$0] ?? 2,
                                sets: templates[$0]?.map { set($0, template: true) } ?? [WorkoutSet()])
            })
        }
        let active: Session?
        if let raw = root["active"] as? [String: Any] { active = try session(raw) } else { active = nil }
        let data = RepbookData(unit: root["unit"] as? String ?? "lbs", exercises: exercises, routines: converted,
                               workouts: try workouts.map(session), active: active)
        try data.validate(); return data
    }
}
