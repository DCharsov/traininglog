import Foundation
import Testing
@testable import WorkoutCore

@Test func restoringMissingWorkoutKeepsIdentityAndWaitsForFreshAuthority() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object([:]), generation: "g")
    var source = try DemoWorkout.load()
    try source.setField(source.next!, field: "weight", value: "20")
    let restored = try await store.restoreMissing(source, generation: "g")
    #expect(restored.sessions[0].workout == source && !restored.sessions[0].editable)
    let request = try await store.prepareWrite()!
    #expect(request.body["baseVersion"] == .int(0) && request.body["payload"] == source.json)
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == request)
    await #expect(throws: WorkoutError.self) { try await store.apply(id: source.id, action: .field(source.next!, "weight", "30")) }
    _ = try await store.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(1)]))
    #expect(try await store.load().sessions[0].editable == false)
    _ = try await store.acceptSnapshot(.object(["sessionId": .string(source.id), "generation": .string("g"), "version": .int(1), "payload": source.json, "control": .object(["state": .string("phone"), "controlEpoch": .int(0)])]))
    #expect(try await store.load().sessions[0].editable)
    #expect(try await store.recoveryArchives().count == 1)
}

@Test func generationRecoveryArchivesOldOutboxAndNeverGrantsEditingWithoutServerControl() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    let workout = try DemoWorkout.load()
    let export: JSONValue = .object(["sessions": .array([workout.json]), "programs": .array([]), "equipment": .array([])])
    _ = try await store.importServer(export, generation: "old")
    let equipment: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Не отправлено"), "mode": .string("MachineStack")])
    _ = try await store.saveDocument(kind: "equipment", payload: equipment, version: 0)
    let pending = try await store.prepareWrite()!
    let next = try await store.adoptGeneration("new", export: export)
    #expect(next.generation == "new")
    #expect(next.sessions.count == 1 && !next.sessions[0].editable)
    #expect(try await store.prepareWrite() == nil)
    #expect(try await PhoneDiary(directory: directory).load().generation == "new")
    let archives = try await store.recoveryArchives()
    #expect(archives.count == 1)
    let archived = archives[0].payload!
    #expect(archived["diary"]["documentWrites"].array[0]["body"] == pending.body)
    #expect(archived["diary"]["sessions"].array[0]["workout"]["json"] == workout.json)
    #expect(archived["server"] == export)
    await #expect(throws: WorkoutError.self) { try await store.adoptGeneration("new", export: export) }
}

@Test func invalidGenerationSnapshotLeavesOriginalDiaryAndQueueUntouched() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object([:]), generation: "old")
    await #expect(throws: WorkoutError.self) { try await store.adoptGeneration("new", export: .object([:])) }
    #expect(try await store.load().generation == "old")
    #expect(try await store.recoveryArchives().isEmpty)
}
