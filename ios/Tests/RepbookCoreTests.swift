import XCTest
@testable import RepbookCore

final class RepbookCoreTests: XCTestCase {
    func testProgressionExcludesWarmupsAndAggregatesWorkingSets() throws {
        let date = Date()
        let exercise = Exercise(name: "Row")
        let session = Session(name: "Upper", started: date, exercises: [SessionExercise(exerciseID: exercise.id, sets: [
            WorkoutSet(weight: 500, reps: 10, warmup: true, done: true),
            WorkoutSet(weight: 100, reps: 8, done: true),
            WorkoutSet(weight: 110, reps: 6, done: true),
            WorkoutSet(weight: 999, reps: 10, done: false)
        ])])
        let data = RepbookData(exercises: [exercise], routines: [], workouts: [session])
        XCTAssertEqual(data.progression(months: nil, metric: .weight, now: date).first?.points.first?.value, 110)
        XCTAssertEqual(data.progression(months: nil, metric: .reps, now: date).first?.points.first?.value, 14)
        XCTAssertEqual(data.progression(months: nil, metric: .volume, now: date).first?.points.first?.value, 1460)
        XCTAssertEqual(data.weightRecords.first?.weight, 110)
        XCTAssertTrue(data.progression(months: 1, metric: .weight, now: date.addingTimeInterval(100 * 86400)).isEmpty)
    }
    func testWarmupsAndHistory() throws {
        var data = RepbookData.seed()
        data.routines[0].exercises[0].sets = [WorkoutSet(weight: 100, reps: 8)]
        var session = data.starting(data.routines[0])
        XCTAssertEqual(session.exercises[0].sets.map(\.weight), [50, 75, 100])
        XCTAssertEqual(session.exercises[0].sets.map(\.reps), [8, 4, 8])
        session.exercises[0].sets[2].weight = 110; session.exercises[0].sets[2].done = true
        data.workouts = [session]
        data.routines[0].exercises[0].warmupCount = 1
        let next = data.starting(data.routines[0])
        XCTAssertEqual(next.exercises[0].sets.count, 2)
        XCTAssertEqual(next.exercises[0].sets[1].weight, 110)
        XCTAssertFalse(next.exercises[0].sets[1].done)
        XCTAssertEqual(next.exercises[0].sets[0].weight, 70)
        try data.validate()
    }
    func testImportWebBackupPreservesRoutinesAndActiveWorkout() throws {
        let json = #"{"unit":"lbs","exercises":[{"id":"row","name":"Wide Grip Seated Row (Machine)"}],"warmupCounts":{"row":1},"routines":[{"id":"upper","name":"Upper","exerciseIds":["row"],"templates":{"row":[{"weight":"100","reps":"8"}]}}],"workouts":[],"active":{"id":"active","name":"Upper","start":"2026-10-25T10:00:00.000Z","exercises":[{"exerciseId":"row","sets":[{"type":"warmup","weight":"","reps":"","previousWeight":65,"previousReps":6,"done":false},{"weight":"105","reps":"9","done":true}]}]}}"#
        let data = try BackupImporter.decode(Data(json.utf8))
        XCTAssertEqual(data.routines[0].exercises[0].warmupCount, 1)
        XCTAssertEqual(data.routines[0].exercises[0].sets[0].weight, 100)
        XCTAssertEqual(data.active?.exercises[0].sets[0].weight, 65)
        XCTAssertEqual(data.active?.completedSets, 1)
        XCTAssertEqual(data.active?.nextSet?.set, 0)
    }
    func testInvalidReferenceRejected() {
        var data = RepbookData.seed(); data.routines[0].exercises[0].exerciseID = "missing"
        XCTAssertThrowsError(try data.validate())
    }
    func testImportedHevyHistoryWithNullEnd() throws {
        let json = #"{"unit":"lbs","exercises":[{"id":"x","name":"Row"}],"routines":[],"workouts":[{"id":"w","name":"Upper","start":"2026-10-23T10:05:00.000Z","end":null,"source":"hevy","exercises":[{"exerciseId":"x","sets":[{"weight":"105","reps":"9","done":true}]}]}],"active":null}"#
        let data = try BackupImporter.decode(Data(json.utf8))
        XCTAssertEqual(data.workouts[0].completedSets, 1)
        XCTAssertNil(data.workouts[0].ended)
    }
    func testUnitConversionIncludesHistoryAndActiveWorkout() {
        var data = RepbookData.seed(); data.routines[0].exercises[0].sets[0].weight = 100
        data.active = data.starting(data.routines[0]); data.workouts = [data.active!]
        data.convertUnit(to: "kg")
        XCTAssertEqual(data.routines[0].exercises[0].sets[0].weight, 45.36)
        XCTAssertEqual(data.active?.exercises[0].sets.last?.weight, 45.36)
        XCTAssertEqual(data.workouts[0].exercises[0].sets.last?.weight, 45.36)
    }
    func testBackupRoundTrip() throws {
        let data = RepbookData.seed(); let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try BackupImporter.decode(encoder.encode(data)), data)
    }

    func testLoggingAdvancesToNextSet() {
        var session = RepbookData.seed().starting(RepbookData.seed().routines[0])
        let first = session.nextSet
        XCTAssertNotNil(first)
        session.exercises[first!.exercise].sets[first!.set].done = true
        XCTAssertNotEqual(session.nextSet?.set, first?.set)
        XCTAssertEqual(session.completedSets, 1)
    }

    func testPreviousNativeBuildDataStillDecodes() throws {
        let original = RepbookData.seed()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        if var routines = object["routines"] as? [[String: Any]] {
            for routineIndex in routines.indices {
                guard var exercises = routines[routineIndex]["exercises"] as? [[String: Any]] else { continue }
                for exerciseIndex in exercises.indices {
                    guard var sets = exercises[exerciseIndex]["sets"] as? [[String: Any]] else { continue }
                    for setIndex in sets.indices {
                        sets[setIndex].removeValue(forKey: "weightPR")
                        sets[setIndex].removeValue(forKey: "volumePR")
                    }
                    exercises[exerciseIndex]["sets"] = sets
                }
                routines[routineIndex]["exercises"] = exercises
            }
            object["routines"] = routines
        }
        let restored = try BackupImporter.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.routines.count, original.routines.count)
        XCTAssertEqual(restored.exercises.count, original.exercises.count)
    }
}
