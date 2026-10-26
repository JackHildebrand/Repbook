import ActivityKit
import Combine
import Foundation

@MainActor
final class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()
    @Published private(set) var data: RepbookData
    @Published var error: String?
    private let url: URL
    private var activityTask: Task<Void, Never>?
    private var storageHealthy = true

    private init() {
        url = URL.applicationSupportDirectory.appending(path: "Repbook/data.json")
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

    func finish() {
        guard var session = data.active else { return }
        session.ended = Date(); session.restUntil = nil
        session.exercises = session.exercises.map { item in var item = item; item.sets.removeAll { !$0.done }; return item }
        session.exercises.removeAll { $0.sets.isEmpty }
        guard session.completedSets > 0 else { error = "Log at least one set before finishing."; return }
        change { $0.workouts.insert(session, at: 0); $0.active = nil }
    }

    func toggleSet(exercise ei: Int, set si: Int) {
        guard let active = data.active, active.exercises.indices.contains(ei), active.exercises[ei].sets.indices.contains(si) else { return }
        change {
            $0.active!.exercises[ei].sets[si].done.toggle()
            $0.active!.restUntil = $0.active!.exercises[ei].sets[si].done && $0.restSeconds > 0 ? Date().addingTimeInterval(Double($0.restSeconds)) : nil
        }
    }

    func adjustCurrent(sessionID: String, setID: String, weight: Double, reps: Int) async {
        guard let session = data.active, session.id == sessionID, let next = session.nextSet,
              session.exercises[next.exercise].sets[next.set].id == setID else { return }
        change {
            $0.active!.exercises[next.exercise].sets[next.set].weight = max(0, session.exercises[next.exercise].sets[next.set].weight + weight)
            $0.active!.exercises[next.exercise].sets[next.set].reps = min(999, max(1, session.exercises[next.exercise].sets[next.set].reps + reps))
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

    func scheduleActivityUpdate() {
        let previous = activityTask
        activityTask = Task { [weak self] in
            await previous?.value
            await self?.syncActivity()
        }
    }

    private func syncActivity() async {
        guard let session = data.active else {
            for activity in Activity<WorkoutAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let next = session.nextSet
        let set = next.map { session.exercises[$0.exercise].sets[$0.set] }
        let state = WorkoutAttributes.ContentState(
            exercise: next.map { name(session.exercises[$0.exercise].exerciseID) } ?? "All sets logged",
            setID: set?.id ?? "", label: next.map { "\(set?.warmup == true ? "Warmup" : "Set") \($0.set + 1)" } ?? "Finish in Repbook",
            weight: set?.weight ?? 0, reps: set?.reps ?? 0, unit: data.unit, completed: session.completedSets,
            restUntil: session.restUntil, finished: next == nil)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<WorkoutAttributes>.activities where activity.attributes.sessionID != session.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let activity = Activity<WorkoutAttributes>.activities.first(where: { $0.attributes.sessionID == session.id }) {
            await activity.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity.request(attributes: WorkoutAttributes(sessionID: session.id, name: session.name, started: session.started), content: content, pushType: nil)
            } catch { self.error = "Workout saved. Live Activity could not start: \(error.localizedDescription)" }
        }
    }
}
