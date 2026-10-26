import ActivityKit
import AppIntents
import Foundation

struct WeeklyRoutineConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Weekly routine schedule"
    static var description = IntentDescription("Enter the exact name of a Repbook routine for each day. Leave a day empty for rest.")
    @Parameter(title: "Monday", default: "Upper") var monday: String
    @Parameter(title: "Tuesday", default: "Lower") var tuesday: String
    @Parameter(title: "Wednesday", default: "Upper") var wednesday: String
    @Parameter(title: "Thursday", default: "Lower") var thursday: String
    @Parameter(title: "Friday", default: "") var friday: String
    @Parameter(title: "Saturday", default: "") var saturday: String
    @Parameter(title: "Sunday", default: "") var sunday: String

    var routineNames: [String] { [sunday, monday, tuesday, wednesday, thursday, friday, saturday] }
    func routine(on date: Date) -> String {
        routineNames[Calendar.current.component(.weekday, from: date) - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var encodedSchedule: String {
        (try? String(data: JSONEncoder().encode(routineNames), encoding: .utf8)) ?? "[]"
    }
}

struct StartScheduledWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start scheduled workout"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Weekly schedule") var schedule: String
    init() {}
    init(schedule: String) { self.schedule = schedule }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let names = try JSONDecoder().decode([String].self, from: Data(schedule.utf8))
        guard names.count == 7 else { throw ScheduledWorkoutError.invalidSchedule }
        let name = names[Calendar.current.component(.weekday, from: Date()) - 1].trimmingCharacters(in: .whitespacesAndNewlines)
        try await WorkoutStore.shared.startScheduledRoutine(named: name)
        #endif
        return .result()
    }
}

enum ScheduledWorkoutError: LocalizedError {
    case invalidSchedule, restDay, missingRoutine, saveFailed, activitiesDisabled
    var errorDescription: String? {
        switch self {
        case .invalidSchedule: "Edit this widget to set your weekly schedule."
        case .restDay: "Today is a rest day. Edit the widget to schedule a routine."
        case .missingRoutine: "No routine matches today's scheduled name. Check the name in Edit Widget against your Repbook routines."
        case .saveFailed: "The workout could not be saved. Open Repbook to check your data."
        case .activitiesDisabled: "Enable Live Activities for Repbook in iPhone Settings before starting from the widget."
        }
    }
}

struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setID: String
        var label: String
        var progress: String
        var weight: Double
        var reps: Int
        var unit: String
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
