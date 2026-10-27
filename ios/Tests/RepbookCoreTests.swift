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

extension RepbookCoreTests {
    func testScheduleRestAndNotesRoundTripAndOldBackups() throws {
        var data = RepbookData.seed()
        data.weekdayRoutines = ["2": data.routines[0].id]
        data.routines[0].exercises[0].restSeconds = 90
        data.routines[0].exercises[0].notes = "Slow eccentric"
        data.routines[0].exercises[0].warmupCount = 4
        data.routines[0].exercises[0].sets[0].weight = 100
        let session = data.starting(data.routines[0])
        XCTAssertEqual(session.exercises[0].restSeconds, 90)
        XCTAssertEqual(session.exercises[0].notes, "Slow eccentric")
        XCTAssertEqual(session.exercises[0].sets.filter(\.warmup).count, 4)
        XCTAssertTrue(session.exercises[0].sets.allSatisfy { !$0.done })
        try data.validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try BackupImporter.decode(encoder.encode(data)), data)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(data)) as? [String: Any])
        old.removeValue(forKey: "weekdayRoutines")
        var routines = try XCTUnwrap(old["routines"] as? [[String: Any]])
        for i in routines.indices {
            var exercises = try XCTUnwrap(routines[i]["exercises"] as? [[String: Any]])
            for j in exercises.indices { exercises[j].removeValue(forKey: "notes"); exercises[j].removeValue(forKey: "restSeconds") }
            routines[i]["exercises"] = exercises
        }
        old["routines"] = routines
        XCTAssertNil(try BackupImporter.decode(JSONSerialization.data(withJSONObject: old)).weekdayRoutines)
    }

    func testFocusedSetResumesAndAdvancesWhenLogged() {
        var data = RepbookData.seed()
        var session = data.starting(data.routines[0])
        let target = session.exercises[1].sets[1].id
        session.focusedSetID = target
        XCTAssertEqual(session.nextSet?.exercise, 1)
        XCTAssertEqual(session.nextSet?.set, 1)
        session.exercises[1].sets[1].done = true
        XCTAssertEqual(session.nextSet?.exercise, 0)
        XCTAssertEqual(session.nextSet?.set, 0)
        data.active = session
        XCTAssertNoThrow(try data.validate())
    }

    func testHevyCSVImportIsAtomicDeduplicatedAndConvertsUnits() throws {
        let csv = "\"title\",\"start_time\",\"end_time\",\"exercise_title\",\"set_type\",\"weight_lbs\",\"reps\",\"exercise_notes\"\n\"Upper\",\"23 Oct 2026, 10:05\",\"23 Oct 2026, 11:07\",\"Lateral Raise (Machine)\",\"warmup\",50,8,\"slow, controlled\"\n\"Upper\",\"23 Oct 2026, 10:05\",\"23 Oct 2026, 11:07\",\"Lateral Raise (Machine)\",\"normal\",100,9,\"slow, controlled\"\n"
        var original = RepbookData.seed(); original.unit = "kg"
        let result = try HevyCSVImporter.merge(csv, into: original, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.data.workouts.first?.completedSets, 2)
        XCTAssertEqual(result.data.workouts.first?.exercises.first?.sets.last?.weight, 45.36)
        XCTAssertEqual(result.data.workouts.first?.exercises.first?.notes, "slow, controlled")
        XCTAssertEqual(result.data.routines, original.routines)
        let duplicate = try HevyCSVImporter.merge(csv, into: result.data, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(duplicate.imported, 0)
        XCTAssertEqual(duplicate.skipped, 1)
        XCTAssertEqual(duplicate.data.workouts.count, 1)
        XCTAssertEqual(original.workouts.count, 0)
        XCTAssertThrowsError(try HevyCSVImporter.merge(csv.replacingOccurrences(of: ",100,9,", with: ",100,0,"), into: original))
    }

    func testCSVHandlesMultilineEscapesAndRejectsBrokenQuotes() throws {
        let rows = try HevyCSVImporter.parse("a,b\n\"line 1\nline 2\",\"a \"\"quote\"\"\"\n")
        XCTAssertEqual(rows[1], ["line 1\nline 2", "a \"quote\""])
        XCTAssertThrowsError(try HevyCSVImporter.parse("a,b\n\"unclosed"))
    }

    func testEstimatedMaxAndAllExercisesAreAvailable() {
        let exercises = (0..<8).map { Exercise(name: "Exercise \($0)") }
        let session = Session(name: "Full body", exercises: exercises.map { SessionExercise(exerciseID: $0.id, sets: [WorkoutSet(weight: 100, reps: 9, done: true)]) })
        let data = RepbookData(exercises: exercises, routines: [], workouts: [session])
        let trends = data.progression(months: nil, metric: .estimatedMax)
        XCTAssertEqual(trends.count, 8)
        XCTAssertEqual(trends.first?.points.first?.value, 130)
    }

    func testRecomputingVolumeRecordsAfterHistoricalEdit() {
        let exercise = Exercise(name: "Row")
        let first = Session(name: "First", started: Date(timeIntervalSince1970: 1), exercises: [SessionExercise(exerciseID: exercise.id, sets: [WorkoutSet(weight: 100, reps: 10, done: true)])])
        let second = Session(name: "Second", started: Date(timeIntervalSince1970: 2), exercises: [SessionExercise(exerciseID: exercise.id, sets: [WorkoutSet(weight: 110, reps: 10, done: true)])])
        var data = RepbookData(exercises: [exercise], routines: [], workouts: [second, first])
        data.recalculateVolumeRecords()
        XCTAssertEqual(data.workouts[0].exercises[0].sets[0].volumePR, true)
        data.workouts[1].exercises[0].sets[0].weight = 120
        data.recalculateVolumeRecords()
        XCTAssertEqual(data.workouts[0].exercises[0].sets[0].volumePR, false)
    }
}
