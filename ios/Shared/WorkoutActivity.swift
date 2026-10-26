import ActivityKit
import AppIntents
import Foundation

struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setID: String
        var label: String
        var weight: Double
        var reps: Int
        var unit: String
        var completed: Int
        var restUntil: Date?
        var finished: Bool
    }
    var sessionID: String
    var name: String
    var started: Date
}

struct AdjustSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Adjust current set"
    static var description = IntentDescription("Changes the weight or reps for Repbook's current set.")
    static var isDiscoverable: Bool = false
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String
    @Parameter(title: "Weight change") var weightDelta: Double
    @Parameter(title: "Rep change") var repDelta: Int
    init() {}
    init(sessionID: String, setID: String, weightDelta: Double = 0, repDelta: Int = 0) {
        self.sessionID = sessionID; self.setID = setID; self.weightDelta = weightDelta; self.repDelta = repDelta
    }
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WorkoutStore.shared.adjustCurrent(sessionID: sessionID, setID: setID, weight: weightDelta, reps: repDelta)
        #endif
        return .result()
    }
}

struct LogSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log current set"
    static var description = IntentDescription("Logs Repbook's current set and advances to the next set.")
    static var isDiscoverable: Bool = false
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Set") var setID: String
    init() {}
    init(sessionID: String, setID: String) { self.sessionID = sessionID; self.setID = setID }
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await WorkoutStore.shared.logCurrent(sessionID: sessionID, setID: setID)
        #endif
        return .result()
    }
}
