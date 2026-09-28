import Foundation
import Testing
@testable import WorkoutCore

@Test func historyCorrectionPreservesIdentityTimingAndIsAtomic() throws {
    var workout = try DemoWorkout.load(); let location = workout.next!
    try workout.setField(location, field: "weight", value: "10")
    try workout.setField(location, field: "reps", value: "8")
    try workout.complete(location, now: Date(timeIntervalSince1970: 1000))
    try workout.finish(now: Date(timeIntervalSince1970: 2000))
    let original = workout
    #expect(throws: WorkoutError.self) { try workout.correctHistory(location, values: ["weight": "12", "reps": "bad"]) }
    #expect(workout == original)
    try workout.correctHistory(location, values: ["weight": "12,5", "reps": "10", "rir": "2"])
    #expect(workout.record(at: location)["loadGrams"].integer == 12500)
    #expect(workout.record(at: location)["count"].integer == 10)
    #expect(workout.record(at: location)["completedAt"] == original.record(at: location)["completedAt"])
    #expect(workout.record(at: location)["id"] == original.record(at: location)["id"])
    #expect(workout.json["completedAt"] == original.json["completedAt"])
    #expect(workout.restEndsAt == original.restEndsAt)
    #expect(!workout.active)
    let skipped = workout.sequence.first { workout.record(at: $0)["status"].string == "skipped" }!
    #expect(throws: WorkoutError.self) { try workout.correctHistory(skipped, values: ["reps": "10"]) }
}

@Test func historyCorrectionUsesVersionedDurableOutbox() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var workout = try DemoWorkout.load(); let location = workout.next!
    try workout.setField(location, field: "weight", value: "10"); try workout.setField(location, field: "reps", value: "8")
    try workout.complete(location, now: Date()); try workout.finish(now: Date())
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object(["sessions": .array([workout.json])]), generation: "g")
    await #expect(throws: WorkoutError.self) { try await store.correctHistory(id: workout.id, location: location, values: ["weight": "12"]) }
    var snapshot: JSONValue = .object(["sessionId": .string(workout.id), "generation": .string("g"), "version": .int(7), "payload": workout.json, "control": .object(["state": .string("phone"), "controlEpoch": .int(3)])])
    _ = try await store.acceptSnapshot(snapshot)
    _ = try await store.correctHistory(id: workout.id, location: location, values: ["weight": "12"])
    let restarted = PhoneDiary(directory: directory)
    let beforeStaleDraft = try await restarted.load()
    await #expect(throws: WorkoutError.self) {
        try await restarted.correctHistory(id: workout.id, location: location, values: ["weight": "99"], expectedRecord: workout.record(at: location))
    }
    #expect(try await restarted.load().sessions[0].workout == beforeStaleDraft.sessions[0].workout)
    let request = try await store.prepareWrite()!
    #expect(request.body["baseVersion"].integer == 7)
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == request)
    _ = try await store.correctHistory(id: workout.id, location: location, values: ["weight": "15"])
    #expect(try await store.prepareWrite() == request)
    _ = try await store.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(8)]))
    #expect(try await store.load().sessions[0].dirty)
    snapshot["control"]["state"] = .string("watch")
    _ = try await store.acceptSnapshot(snapshot)
    await #expect(throws: WorkoutError.self) { try await store.correctHistory(id: workout.id, location: location, values: ["weight": "20"]) }
}
