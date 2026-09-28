import Foundation
import Testing
@testable import WorkoutCore

private func fixture() throws -> Workout { try DemoWorkout.load() }
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func shared(_ name: String) throws -> JSONValue {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { root.deleteLastPathComponent() }
    return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: root.appendingPathComponent("tests/contracts/watch/\(name).json")))
}

@Test func sharedContractAndBundledFixture() throws {
    let raw = try shared("session"), expected = try shared("expectations"), w = try Workout(json: raw)
    #expect(try fixture().json == raw)
    #expect(w.sequence.map { Int64($0.setID.suffix(12))! } == expected["sequenceSuffixes"].array.compactMap(\.integer))
    #expect(w.exercises.map(RestRules.seconds) == expected["rests"].array.compactMap(\.integer))
    for pair in expected["weights"].array { #expect(try Workout.parseWeight(pair.array[0].string!) == pair.array[1].integer) }
    for input in expected["invalidWeights"].array { #expect(throws: WorkoutError.self) { try Workout.parseWeight(input.string!) } }
}

@Test func fullSyntheticWorkoutSurvivesEveryRestart() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    var store = WorkoutStore(directory: dir)
    var state = try await store.beginDemo(fixture())
    let total = state.workout.sequence.count
    for _ in 0..<total {
        let location = state.selected!, e = state.workout.exercise(at: location)
        if e["mode"].string != "BodyweightOnly" { state = try await store.apply(.field(location, "weight", "12,5")) }
        state = try await store.apply(.field(location, e["tracking"].string == "duration" ? "duration" : "reps", "10"))
        state = try await store.apply(.complete(location), now: now)
        store = WorkoutStore(directory: dir)
        #expect(try await store.load() == state)
    }
    #expect(state.selected == nil)
    state = try await store.apply(.finish, now: now)
    #expect(state.workout.sequence.allSatisfy { state.workout.record(at: $0)["status"].string == "completed" })
    #expect(try await WorkoutStore(directory: dir).load() == state)
}
private func fill(_ w: inout Workout, _ loc: SetLocation, weight: String = "12,5", count: String = "10") throws {
    try w.setField(loc, field: "weight", value: weight)
    try w.setField(loc, field: w.exercise(at: loc)["tracking"].string == "duration" ? "duration" : "reps", value: count)
}

@Test func decimalWeights() throws {
    for (input, grams) in [("72,5", Int64(72500)), ("0.001", 1), ("2000", 2000000), (" 12.125 ", 12125)] {
        #expect(try Workout.parseWeight(input) == grams)
        #expect(try Workout.parseWeight(Workout.formatWeight(grams)) == grams)
    }
    for input in ["-1", "2e2", "1.0001", "2000.001", "", "1,", "1 000"] {
        #expect(throws: WorkoutError.self) { try Workout.parseWeight(input) }
    }
}

@Test func repeatKeepsIdentityAndUnknownFields() throws {
    var w = try fixture()
    let first = w.sequence[0], second = w.sequence[1], original = w.record(at: second)
    try fill(&w, first); try w.setField(first, field: "rir", value: "2"); try w.setField(first, field: "note", value: "Не копировать")
    #expect(try w.complete(first, now: now))
    #expect(try !w.complete(first, now: now))
    #expect(try w.autofill(second))
    let r = w.record(at: second)
    #expect(r["weight"].string == "12,5" && r["reps"].string == "10")
    #expect(r["id"] == original["id"] && r["completedAt"] == .null && r["status"].string == "draft")
    #expect(r["rir"].string == "" && r["note"].string == "" && r["loadGrams"] == .null)
    let roundTrip = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(w))
    #expect(roundTrip == w)
    #expect(w.json["futureSession"]["preserve"].array.count == 2)
    #expect(w.exercises[0]["futureExercise"]["preserve"].bool)
}

@Test func manualInputAndSidesAndKinds() throws {
    var w = try fixture()
    let locations = w.sequence.filter { w.exercise(at: $0)["unilateral"].bool }
    try fill(&w, locations[0]); try w.complete(locations[0], now: now)
    #expect(try !w.autofill(locations[1]))
    #expect(try w.autofill(locations[2]))
    try fill(&w, locations[1], weight: "8", count: "9"); try w.complete(locations[1], now: now)
    #expect(try w.autofill(locations[3]))
    #expect(w.record(at: locations[3])["weight"].string == "8")
    let regular = w.sequence[0], next = w.sequence[1]
    try fill(&w, regular); try w.complete(regular, now: now)
    try w.setField(next, field: "reps", value: "5")
    #expect(try !w.autofill(next))
    #expect(w.record(at: next)["weight"].string == "")
    let kinds = w.sequence.filter { w.exercise(at: $0)["mode"].string == "AssistedBodyweight" }
    try fill(&w, kinds[0]); try w.complete(kinds[0], now: now)
    #expect(try !w.autofill(kinds[1]))
}

@Test func durationAndCorrectionAndFinish() throws {
    var w = try fixture()
    let locations = w.sequence.filter { w.exercise(at: $0)["tracking"].string == "duration" }
    try fill(&w, locations[0], count: "45"); try w.complete(locations[0], now: now)
    let end = w.restEndsAt
    #expect(w.record(at: locations[0])["loadGrams"] == .null)
    #expect(try w.autofill(locations[1]))
    #expect(w.record(at: locations[1])["duration"].string == "45")
    try w.correct(locations[0]); try w.setField(locations[0], field: "duration", value: "50")
    try w.complete(locations[0], now: now.addingTimeInterval(10))
    #expect(w.restEndsAt == end)
    try w.finish(now: now)
    #expect(!w.active && w.restEndsAt == nil)
    #expect(w.sequence.filter { w.record(at: $0)["status"].string == "completed" }.count == 1)
    #expect(w.sequence.allSatisfy { w.record(at: $0)["status"].string != "draft" })
}

@Test func orderingRestAndWeightProfile() throws {
    let w = try fixture(), seq = w.sequence
    #expect(seq[3].exerciseID == w.exercises[1]["id"].string)
    #expect(seq[4].exerciseID == w.exercises[2]["id"].string)
    #expect(seq[5].exerciseID == seq[3].exerciseID)
    #expect(RestRules.seconds(w.exercises[0]) == 150)
    #expect(RestRules.seconds(w.exercises[1]) == 30)
    #expect(RestRules.seconds(w.exercises[4]) == 60)
    #expect(try Workout.adjustedWeight(w.exercises[0], input: "10", direction: 1) == "12,5")
    #expect(try Workout.adjustedWeight(w.exercises[0], input: "12,5", direction: -1) == "10")
}

@Test func unsupportedEnumDoesNotBecomeEmpty() throws {
    var raw = try fixture().json, all = raw["exercises"].array
    all[0]["mode"] = .string("NewFutureMode"); raw["exercises"] = .array(all)
    #expect(throws: WorkoutError.self) { try Workout(json: raw) }
}

@Test func diskRestartAndDuplicateAndWriteFailure() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir)
    let start = try await store.beginDemo(fixture()), loc = start.selected!
    _ = try await store.apply(.field(loc, "weight", "12,5"))
    _ = try await store.apply(.field(loc, "reps", "10"))
    let done = try await store.apply(.complete(loc), now: now)
    let duplicate = try await store.apply(.complete(loc), now: now)
    #expect(done == duplicate)
    #expect(done.workout.record(at: done.selected!)["weight"].string == "12,5")
    let reopened = try await WorkoutStore(directory: dir).load()
    #expect(reopened == done)
    // Replace the destination with a directory to force persistence to fail.
    let file = dir.appendingPathComponent("workout-state.json"), saved = dir.appendingPathComponent("saved.json")
    try FileManager.default.moveItem(at: file, to: saved)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    do { _ = try await store.apply(.skip(done.selected!)); Issue.record("Expected disk failure") } catch { }
    #expect(try await store.load() == done)
}

@Test func corruptFilePreserved() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("workout-state.json"), data = Data("broken".utf8)
    try data.write(to: file)
    do { _ = try await WorkoutStore(directory: dir).load(); Issue.record("Expected corruption error") } catch { }
    #expect(try Data(contentsOf: file) == data)
}
