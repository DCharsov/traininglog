import Foundation
import Testing
@testable import WorkoutCore

@Test func progressSeparatesEquipmentModesAndExcludesDraftsWarmups() throws {
    var workout = try DemoWorkout.load(); let l = workout.next!
    try workout.setField(l, field: "weight", value: "12,5"); try workout.setField(l, field: "reps", value: "10")
    try workout.complete(l, now: .now)
    #expect(TrainingProgress.results([workout.json]).isEmpty)
    try workout.finish(now: .now)
    let rows = TrainingProgress.results([workout.json])
    #expect(rows.count == 1)
    #expect(TrainingProgress.volume(rows) == 125)
    #expect(TrainingProgress.points(rows, metric: "load").first?.value == 12500)
    #expect(TrainingProgress.points(rows, metric: "reps", weight: 12500).first?.value == 10)
    #expect(TrainingProgress.points(rows, metric: "reps", weight: 15000).isEmpty)
    var other = workout.exercise(at: l); other["equipmentId"] = .string(UUID().uuidString)
    #expect(TrainingProgress.results([workout.json], context: TrainingProgress.Context(other)).isEmpty)
    other = workout.exercise(at: l); other["mode"] = .string("BarbellTotal")
    #expect(TrainingProgress.results([workout.json], context: TrainingProgress.Context(other)).isEmpty)
    var deleted = workout.json; deleted["deletedAt"] = .string("2026-09-28T00:00:00Z")
    #expect(TrainingProgress.results([deleted]).isEmpty)
}

@Test func assistedProgressChoosesLessAssistanceAndNeverTonnage() throws {
    var workout = try DemoWorkout.load()
    let exercise = workout.exercises.first { $0["mode"].string == "AssistedBodyweight" }!
    let locations = workout.sequence.filter { $0.exerciseID == exercise["id"].string }
    for (i, l) in locations.prefix(2).enumerated() {
        try workout.setField(l, field: "weight", value: i == 0 ? "30" : "25")
        try workout.setField(l, field: "reps", value: "10"); try workout.complete(l, now: .now)
    }
    try workout.finish(now: .now)
    let rows = TrainingProgress.results([workout.json], context: TrainingProgress.Context(exercise))
    #expect(TrainingProgress.points(rows, metric: "load").first?.value == 25000)
    #expect(TrainingProgress.volume(rows) == nil)
    #expect(TrainingProgress.elapsedMinutes(.object(["status": .string("completed"), "startedAt": .string("2026-09-28T10:00:00Z"), "completedAt": .string("2026-09-28T11:30:00.000Z")] )) == 90)
}
