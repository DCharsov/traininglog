import Foundation
import Testing
@testable import WorkoutCore

@Test func recoveryUsesThreeWayMergeAndRequiresExplicitChoice() throws {
    let base = try DemoWorkout.load(); let location = base.next!
    var local = base, server = base
    try local.setField(location, field: "weight", value: "15")
    #expect(try RecoveryMerge.differences(local: local, server: server, base: base).isEmpty)
    #expect(try RecoveryMerge.merge(local: local, server: server, base: base, useLocal: [:]).record(at: location)["weight"].string == "15")
    try server.setField(location, field: "weight", value: "20")
    #expect(try RecoveryMerge.differences(local: local, server: server, base: base).count == 1)
    #expect(throws: WorkoutError.self) { try RecoveryMerge.merge(local: local, server: server, base: base, useLocal: [:]) }
    #expect(try RecoveryMerge.merge(local: local, server: server, base: base, useLocal: [location.id: false]).record(at: location)["weight"].string == "20")
}

@Test func controlReturnIsDurableAndNeverUnlocksBeforeAck() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = PhoneDiary(directory: dir); let workout = try DemoWorkout.load()
    _ = try await store.importServer(.object(["sessions": .array([workout.json])]), generation: "g")
    var snapshot: JSONValue = .object(["sessionId": .string(workout.id), "generation": .string("g"), "version": .int(2), "payload": workout.json, "control": .object(["state": .string("offered"), "controlEpoch": .int(1), "handoffId": .string("offer")])])
    _ = try await store.acceptSnapshot(snapshot)
    let request = try await store.prepareControl(id: workout.id, force: false)
    #expect(request.body["handoffId"].string == "offer")
    #expect(try await PhoneDiary(directory: dir).prepareWrite() == request)
    #expect(try await store.load().active?.editable == false)
    snapshot["version"] = .int(3); snapshot["control"]["state"] = .string("phone"); snapshot["control"]["controlEpoch"] = .int(2)
    #expect(try await store.acknowledgeHandoff(request, snapshot: snapshot).active?.editable == true)
}
