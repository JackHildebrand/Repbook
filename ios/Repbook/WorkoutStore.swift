import ActivityKit
import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class WorkoutStore: ObservableObject {
    enum LiveActivityStatus: Equatable {
        case idle
        case starting
        case active
        case disabled
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Not showing"
            case .starting: "Starting…"
            case .active: "Showing on Lock Screen"
            case .disabled: "Disabled in iPhone Settings"
            case .failed: "Could not start"
            }
        }
    }

    static let shared = WorkoutStore()
    @Published private(set) var data: RepbookData
    @Published var error: String?
    @Published var completedSession: Session?
    @Published var currentSetNavigation = UUID()
    @Published var notificationSessionID: String?
    @Published private(set) var liveActivityStatus: LiveActivityStatus = .idle
    private let url: URL
    private var activityTask: Task<Void, Never>?
    private var storageHealthy = true
    private var restTask: Task<Void, Never>?
    private var restKey: String?

    private init() {
        UserDefaults.standard.register(defaults: ["restNotifications": true])
        let testing = ProcessInfo.processInfo.arguments.contains("-repbook-ui-testing")
        url = URL.applicationSupportDirectory.appending(path: testing ? "RepbookUITests/data.json" : "Repbook/data.json")
        if testing && ProcessInfo.processInfo.arguments.contains("-repbook-reset-test-data") { try? FileManager.default.removeItem(at: url) }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                data = try BackupImporter.decode(Data(contentsOf: url))
            } else { data = .seed() }
        } catch {
            data = .seed(); storageHealthy = false
            self.error = "Saved data could not be read. The original file is preserved. Import a backup before making changes."
        }
    }

    func name(_ id: String) -> String { data.exercises.first { $0.id == id }?.name ?? "Exercise" }

    func change(_ action: (inout RepbookData) -> Void) {
        guard storageHealthy else { error = "Import a backup to recover saved data before making changes."; return }
        var updated = data; action(&updated)
        if var session = updated.active {
            for ei in session.exercises.indices {
                let history = updated.workouts.flatMap(\.exercises).filter { $0.exerciseID == session.exercises[ei].exerciseID }.flatMap(\.sets).filter { $0.done && !$0.warmup }
                let best = history.map { $0.weight * Double($0.reps) }.max() ?? 0
                for si in session.exercises[ei].sets.indices {
                    let set = session.exercises[ei].sets[si]
                    session.exercises[ei].sets[si].volumePR = set.done && !set.warmup && set.weight * Double(set.reps) > best
                }
            }
            updated.active = session
        }
        do {
            try updated.validate()
            try persist(updated)
            data = updated
            scheduleActivityUpdate()
        } catch { self.error = error.localizedDescription }
    }

    private func persist(_ updated: RepbookData) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func start(_ routine: Routine) {
        guard data.active == nil else { return }
        change { $0.active = $0.starting(routine) }

    }

    func showLiveActivity() {
        guard data.active != nil else { return }
        scheduleActivityUpdate()
    }

    func startScheduledRoutine(named name: String) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ScheduledWorkoutError.activitiesDisabled }
        if data.active == nil {
            guard !name.isEmpty else { throw ScheduledWorkoutError.restDay }
            guard let routine = data.routines.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
                throw ScheduledWorkoutError.missingRoutine
            }
            start(routine)
            guard data.active != nil else { throw ScheduledWorkoutError.saveFailed }
        } else {
            // Repeated taps resume the active workout instead of creating another one.
            scheduleActivityUpdate()
        }
        await activityTask?.value
        if case .failed(let message) = liveActivityStatus {
            throw NSError(domain: "Repbook.LiveActivity", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func finish() {
        guard var session = data.active else { return }
        for ei in session.exercises.indices {
            let exerciseID = session.exercises[ei].exerciseID
            let previous = historicalSets(for: exerciseID)
            let previousWeight = previous.map(\.weight).max()
            let previousVolume = previous.map { $0.weight * Double($0.reps) }.max()
            for si in session.exercises[ei].sets.indices where session.exercises[ei].sets[si].done && !session.exercises[ei].sets[si].warmup {
                let set = session.exercises[ei].sets[si]
                session.exercises[ei].sets[si].weightPR = previousWeight.map { set.weight > $0 } ?? true
                session.exercises[ei].sets[si].volumePR = set.weight * Double(set.reps) > (previousVolume ?? 0)
            }
        }
        session.ended = Date(); session.restUntil = nil
        session.exercises = session.exercises.map { item in var item = item; item.sets.removeAll { !$0.done }; return item }
        session.exercises.removeAll { $0.sets.isEmpty }
        guard session.completedSets > 0 else { error = "Log at least one set before finishing."; return }
        change { $0.workouts.insert(session, at: 0); $0.active = nil }
        if data.active == nil { completedSession = session }
    }

    func finishFromLiveActivity(sessionID: String) async throws {
        // Ignore repeated taps or actions from a previous session.
        guard let session = data.active, session.id == sessionID else { return }
        guard session.nextSet == nil, session.completedSets > 0 else { return }
        finish()
        guard data.active?.id != sessionID else {
            throw NSError(domain: "Repbook.FinishWorkout", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: error ?? "Could not save the workout. Please try again."])
        }
        // Wait until ActivityKit has dismissed the activity before the intent completes.
        await activityTask?.value
    }

    private func historicalSets(for exerciseID: String) -> [WorkoutSet] {
        data.workouts.flatMap { workout in
            workout.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
        }.filter { $0.done && !$0.warmup }
    }

    func personalRecords(exerciseID: String, set: WorkoutSet) -> (weight: Bool, volume: Bool) {
        guard !set.warmup, set.weight > 0, set.reps > 0 else { return (false, false) }
        let previous = historicalSets(for: exerciseID)
        let weight = previous.map(\.weight).max().map { set.weight > $0 } ?? true
        let volume = previous.map { $0.weight * Double($0.reps) }.max().map { set.weight * Double(set.reps) > $0 } ?? true
        return (weight, volume)
    }

    func toggleSet(exercise ei: Int, set si: Int) {
        guard let active = data.active, active.exercises.indices.contains(ei), active.exercises[ei].sets.indices.contains(si) else { return }
        let target = active.exercises[ei].sets[si]
        let records = personalRecords(exerciseID: active.exercises[ei].exerciseID, set: target)
        change {
            $0.active!.exercises[ei].sets[si].done.toggle()
            let done = $0.active!.exercises[ei].sets[si].done
            $0.active!.exercises[ei].sets[si].weightPR = done && records.weight
            $0.active!.exercises[ei].sets[si].volumePR = done && records.volume
            $0.active!.lastLoggedSetID = done ? target.id : nil
            let seconds = $0.active!.exercises[ei].restSeconds ?? $0.restSeconds
            $0.active!.restUntil = done && seconds > 0 ? Date().addingTimeInterval(Double(seconds)) : nil
        }
        if data.active?.exercises[ei].sets[si].done == true {
            feedback(pr: records.volume)
        }
    }

    func feedback(pr: Bool = false) {
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        if pr { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5) }
    }

    func adjustRest(_ seconds: Int) {
        change {
            guard let end = $0.active?.restUntil else { return }
            $0.active?.restUntil = max(Date(), end.addingTimeInterval(Double(seconds)))
        }
    }

    func adjustCurrent(sessionID: String, setID: String, weight: Double, reps: Int) async {
        guard let session = data.active, session.id == sessionID, let next = session.nextSet,
              session.exercises[next.exercise].sets[next.set].id == setID else { return }
        let configuredWeight = UserDefaults.standard.double(forKey: "weightIncrement")
        let configuredReps = max(1, UserDefaults.standard.integer(forKey: "repIncrement"))
        let weightDelta = weight == 0 ? 0 : (weight < 0 ? -1.0 : 1.0) * (configuredWeight > 0 ? configuredWeight : abs(weight))
        let repDelta = reps == 0 ? 0 : (reps < 0 ? -1 : 1) * configuredReps
        change {
            $0.active!.exercises[next.exercise].sets[next.set].weight = max(0, session.exercises[next.exercise].sets[next.set].weight + weightDelta)
            $0.active!.exercises[next.exercise].sets[next.set].reps = min(999, max(1, session.exercises[next.exercise].sets[next.set].reps + repDelta))
        }
        await activityTask?.value
    }

    func logCurrent(sessionID: String, setID: String) async {
        guard let session = data.active, session.id == sessionID, let next = session.nextSet,
              session.exercises[next.exercise].sets[next.set].id == setID else { return }
        toggleSet(exercise: next.exercise, set: next.set)
        await activityTask?.value
    }

    func importBackup(_ bytes: Data) throws {
        let updated = try BackupImporter.decode(bytes)
        try persist(updated); data = updated; storageHealthy = true; scheduleActivityUpdate()
    }

    func exportBackup() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }

    private func scheduleRestCompletion() {
        guard let session = data.active, let end = session.restUntil else {
            restTask?.cancel(); restTask = nil; restKey = nil; return
        }
        let key = session.id + String(end.timeIntervalSince1970)
        guard restKey != key else { return }
        restTask?.cancel(); restKey = key
        let delay = end.timeIntervalSinceNow
        guard delay > 0 else { return }
        restTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(delay, 86400) * 1_000_000_000)) } catch { return }
            guard let self, !Task.isCancelled, self.restKey == key, self.data.active?.id == session.id,
                  self.data.active?.restUntil == end else { return }
            // Suspension may delay this task. Refresh overdue state without replaying an old alert.
            let recent = Date().timeIntervalSince(end) < 10
            if recent && UIApplication.shared.applicationState == .active { self.feedback() }
            self.enqueueActivityUpdate()
        }
    }

    func scheduleActivityUpdate() {
        RestNotifications.shared.synchronize(session: data.active)
        scheduleRestCompletion()
        enqueueActivityUpdate()
    }

    private func enqueueActivityUpdate() {
        let previous = activityTask
        activityTask = Task { [weak self] in
            await previous?.value
            await self?.syncActivity()
        }
    }

    private func syncActivity() async {
        // UI tests exercise persistence and navigation independently of simulator ActivityKit authorization.
        if ProcessInfo.processInfo.arguments.contains("-repbook-ui-testing") { liveActivityStatus = .disabled; return }
        guard let session = data.active else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["repbook-rest"])
            for activity in Activity<WorkoutAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            liveActivityStatus = .idle
            return
        }
        let next = session.nextSet
        let set = next.map { session.exercises[$0.exercise].sets[$0.set] }
        let progress: String
        if let next, let set {
            let sets = session.exercises[next.exercise].sets
            if set.warmup {
                let warmups = sets.filter(\.warmup)
                let position = sets.prefix(next.set + 1).filter(\.warmup).count
                progress = "W\(position)/\(warmups.count)"
            } else {
                let working = sets.filter { !$0.warmup }
                let position = sets.prefix(next.set + 1).filter { !$0.warmup }.count
                progress = "\(position)/\(working.count)"
            }
        } else { progress = "" }
        let state = WorkoutAttributes.ContentState(
            exercise: next.map { name(session.exercises[$0.exercise].exerciseID) } ?? "All sets logged",
            setID: set?.id ?? "", label: next.map { "\(set?.warmup == true ? "Warmup" : "Set") \($0.set + 1)" } ?? "Ready to finish",
            progress: progress, weight: set?.weight ?? 0, reps: set?.reps ?? 0, unit: data.unit,
            restUntil: session.restUntil, finished: next == nil,
            loggedPR: session.exercises.flatMap(\.sets).first(where: { $0.id == session.lastLoggedSetID }).map { $0.done && $0.volumePR == true })
        var completedState = state
        completedState.restComplete = session.restUntil.map { $0 <= Date() } ?? false
        let content = ActivityContent(state: completedState, staleDate: session.restUntil, relevanceScore: completedState.restComplete == true ? 1.0 : 0.0)
        for activity in Activity<WorkoutAttributes>.activities where activity.attributes.sessionID != session.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let activity = Activity<WorkoutAttributes>.activities.first(where: { $0.attributes.sessionID == session.id }) {
            await activity.update(content)
            liveActivityStatus = .active
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            liveActivityStatus = .starting
            do {
                _ = try Activity.request(attributes: WorkoutAttributes(sessionID: session.id, name: session.name, started: session.started), content: content, pushType: nil)
                liveActivityStatus = .active
            } catch {
                liveActivityStatus = .failed(error.localizedDescription)
                self.error = "Workout saved. Live Activity could not start: \(error.localizedDescription)"
            }
        } else {
            liveActivityStatus = .disabled
        }
    }
}
