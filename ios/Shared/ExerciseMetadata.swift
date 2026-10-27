import Foundation

extension Exercise {
    static let muscleGroups = ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Quads", "Hamstrings", "Glutes", "Calves", "Core", "Adductors", "Abductors"]
    var primaryMuscle: String {
        if let muscleGroup, !muscleGroup.isEmpty { return muscleGroup }
        let known: [String: String] = [
            "Bench Press (Barbell)": "Chest", "Chest Press (Machine)": "Chest", "Chest Fly (Machine)": "Chest",
            "Shoulder Press (Machine)": "Shoulders", "Lateral Raise (Machine)": "Shoulders",
            "Lat Pulldown (Cable)": "Back", "Seated Row (Machine)": "Back", "Wide Grip Seated Row (Machine)": "Back", "Neutral Grip Seated Row (Machine)": "Back",
            "Preacher Curl (Machine)": "Biceps", "Bicep Curl (Dumbbell)": "Biceps", "Triceps Pushdown (Cable)": "Triceps",
            "Squat (Barbell)": "Quads", "Leg Press (Machine)": "Quads", "Leg Extension (Machine)": "Quads",
            "Seated Leg Curl (Machine)": "Hamstrings", "Romanian Deadlift (Barbell)": "Hamstrings",
            "Calf Extension (Machine)": "Calves", "Crunch (Machine)": "Core", "Back Extension (Machine)": "Back",
            "Hip Adduction (Machine)": "Adductors", "Hip Abduction (Machine)": "Abductors"
        ]
        return known[name] ?? "Unassigned"
    }
}

extension Exercise {
    static func displayParts(_ name: String) -> (title: String, equipment: String?) {
        guard name.hasSuffix(")"), let start = name.range(of: " (", options: .backwards) else { return (name, nil) }
        let title = String(name[..<start.lowerBound])
        let equipment = String(name[start.upperBound..<name.index(before: name.endIndex)])
        return (title, equipment)
    }
}
