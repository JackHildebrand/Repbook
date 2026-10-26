import XCTest
@testable import RepbookCore

final class RepbookCoreTests: XCTestCase {
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
}
