import Foundation
import Testing
@testable import WorkoutCore

@Test func structureChangesKeepRecordsAndProgramIdentity() throws {
    var workout = try DemoWorkout.load(); let location = workout.next!
    try workout.setField(location, field: "weight", value: "10"); try workout.setField(location, field: "reps", value: "8")
    try workout.complete(location, now: Date(timeIntervalSince1970: 1000))
    let done = workout.record(at: location)
    let warmed = try workout.changingStructure(.warmup(exerciseID: location.exerciseID))
    #expect(warmed.record(at: location) == done)
    #expect(warmed.exercise(at: location)["records"].array.first?["kind"].string == "warmup")
    #expect(warmed.json["programId"] == workout.json["programId"])
    #expect(warmed.restEndsAt == workout.restEndsAt)
    let reordered = try warmed.changingStructure(.reorder(warmed.exercises.reversed().map { $0["id"].string! }))
    #expect(reordered.record(at: location) == done)
    #expect(throws: WorkoutError.self) { try workout.changingStructure(.reorder([location.exerciseID])) }
    var exercise = workout.exercises[0]; exercise["sets"] = .int(2)
    let added = try workout.changingStructure(.add(exercise))
    let newExercise = added.exercises.last!
    #expect(newExercise["id"] != exercise["id"])
    #expect(newExercise["records"].array.allSatisfy { $0["status"].string == "draft" && $0["completedAt"] == .null && $0["loadGrams"] == .null })
    #expect(Set(added.sequence.map(\.setID)).count == added.sequence.count)
    try workout.finish(now: .now)
    #expect(throws: WorkoutError.self) { try workout.changingStructure(.warmup(exerciseID: location.exerciseID)) }
}

@Test func unilateralWarmupUsesNewPairedIDsAndDoesNotCopyWorkingValues() throws {
    let workout = try DemoWorkout.load()
    let exercise = workout.exercises.first { $0["unilateral"].bool }!
    let changed = try workout.changingStructure(.warmup(exerciseID: exercise["id"].string!))
    let records = changed.exercises.first { $0["id"] == exercise["id"] }!["records"].array
    #expect(records[0]["side"].string == "left")
    #expect(records[1]["side"].string == "right")
    #expect(records[0]["kind"].string == "warmup" && records[1]["kind"].string == "warmup")
    #expect(records[0]["id"] != records[1]["id"])
    #expect(Array(records.dropFirst(2)) == exercise["records"].array)
}
