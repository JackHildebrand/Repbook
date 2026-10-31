import Foundation

enum HevyCSVError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return "Invalid CSV" }
}

struct HevyImportResult {
    let data: RepbookData
    let imported: Int
    let skipped: Int
}

enum HevyCSVImporter {
    static func merge(_ text: String, into original: RepbookData, timeZone: TimeZone = .current) throws -> HevyImportResult {
        let rows = try parse(text)
        guard let headers = rows.first else { throw HevyCSVError.invalid("This CSV is empty.") }
        let columns = Dictionary(headers.enumerated().map { ($0.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.offset) }, uniquingKeysWith: { first, _ in first })
        for name in ["title", "start_time", "exercise_title", "reps"] where columns[name] == nil {
            throw HevyCSVError.invalid("Missing Hevy CSV column: \(name).")
        }
        guard columns["weight_lbs"] != nil || columns["weight_kg"] != nil else { throw HevyCSVError.invalid("No supported weight column found.") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = "dd MMM yyyy, HH:mm"; formatter.isLenient = false
        func date(_ value: String) -> Date? { formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
        var data = original
        var groups: [String: Session] = [:]
        for (rowIndex, row) in rows.dropFirst().enumerated() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            func field(_ name: String) -> String {
                guard let i = columns[name], row.indices.contains(i) else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let title = field("title"), exerciseName = field("exercise_title")
            guard !title.isEmpty, !exerciseName.isEmpty, let started = date(field("start_time")) else { throw HevyCSVError.invalid("Invalid workout or date on CSV row \(rowIndex + 2).") }
            // This weight/reps tracker cannot represent distance-only or timed sets. Fail atomically instead of silently dropping them.
            guard let reps = Int(field("reps")), (1...999).contains(reps) else { throw HevyCSVError.invalid("CSV row \(rowIndex + 2) has no supported rep count. Timed and distance sets are not supported yet. Nothing was imported.") }
            let pounds = columns["weight_lbs"] != nil
            let rawWeight = field(pounds ? "weight_lbs" : "weight_kg")
            let weight = rawWeight.isEmpty ? 0 : Double(rawWeight)
            guard let weight, weight.isFinite, weight >= 0 else { throw HevyCSVError.invalid("Invalid weight on CSV row \(rowIndex + 2).") }
            let converted = original.unit == "kg" ? (pounds ? weight / 2.2046226218 : weight) : (pounds ? weight : weight * 2.2046226218)
            let key = title + "|" + String(started.timeIntervalSince1970)
            if groups[key] == nil {
                let ended = field("end_time").isEmpty ? nil : date(field("end_time"))
                if !field("end_time").isEmpty && ended == nil { throw HevyCSVError.invalid("Invalid end time on CSV row \(rowIndex + 2).") }
                groups[key] = Session(id: "hevy-" + stableID(key), name: title, started: started, ended: ended, exercises: [], notes: field("description").isEmpty ? nil : field("description"))
            }
            let exercise: Exercise
            if let existing = data.exercises.first(where: { $0.name.compare(exerciseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) { exercise = existing }
            else { exercise = Exercise(name: exerciseName); data.exercises.append(exercise) }
            if groups[key]!.exercises.last?.exerciseID != exercise.id {
                groups[key]!.exercises.append(SessionExercise(exerciseID: exercise.id, notes: field("exercise_notes").isEmpty ? nil : field("exercise_notes"), sets: []))
            }
            let ei = groups[key]!.exercises.count - 1
            groups[key]!.exercises[ei].sets.append(WorkoutSet(weight: (converted * 100).rounded() / 100, reps: reps, warmup: field("set_type").lowercased() == "warmup", done: true))
        }
        var imported = 0, skipped = 0
        for session in groups.values.sorted(by: { $0.started < $1.started }) {
            if data.workouts.contains(where: { $0.id == session.id || ($0.name == session.name && abs($0.started.timeIntervalSince(session.started)) < 60) }) { skipped += 1; continue }
            data.workouts.append(session); imported += 1
        }
        // Remove catalog additions that came only from a skipped duplicate.
        let used = Set(data.workouts.flatMap(\.exercises).map(\.exerciseID)).union(original.exercises.map(\.id))
        data.exercises.removeAll { !used.contains($0.id) }
        data.recalculateVolumeRecords()
        try data.validate()
        return HevyImportResult(data: data, imported: imported, skipped: skipped)
    }
    private static func stableID(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
    static func parse(_ text: String) throws -> [[String]] {
        let source = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        let chars = Array(source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if quoted || field.isEmpty { quoted.toggle() }
                else { throw HevyCSVError.invalid("Malformed quoted CSV field.") }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if c == "\n" && !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw HevyCSVError.invalid("Unclosed CSV quote.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

extension RepbookData {
    mutating func recalculateVolumeRecords() {
        var best: [String: Double] = [:]
        for wi in workouts.indices.sorted(by: { workouts[$0].started < workouts[$1].started }) {
            let baseline = best
            for ei in workouts[wi].exercises.indices {
                let id = workouts[wi].exercises[ei].exerciseID
                for si in workouts[wi].exercises[ei].sets.indices {
                    let set = workouts[wi].exercises[ei].sets[si]
                    let volume = set.weight * Double(set.reps)
                    workouts[wi].exercises[ei].sets[si].volumePR = set.done && !set.warmup && volume > baseline[id, default: 0]
                    if set.done && !set.warmup { best[id] = max(best[id, default: 0], volume) }
                }
            }
        }
    }
}
