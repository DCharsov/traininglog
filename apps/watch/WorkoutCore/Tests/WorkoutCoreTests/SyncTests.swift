import Foundation
import Testing
@testable import WorkoutCore

private func offer(_ workout: Workout) -> JSONValue {
    .object(["protocolVersion": .int(1), "contractVersion": .int(2), "sessionId": .string(workout.id), "version": .int(2), "generation": .string("generation"), "payload": workout.json,
        "control": .object(["state": .string("offered"), "deviceId": .string("device"), "controlEpoch": .int(1), "handoffId": .string("handoff")])])
}
private func acknowledgement(version: Int64, epoch: Int64 = 2, state: String = "watch") -> JSONValue {
    .object(["version": .int(version), "generation": .string("generation"), "control": .object(["state": .string(state), "controlEpoch": .int(epoch)])])
}
private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

@Test func acceptIsDurableAndEditorLockedUntilAck() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir), workout = try DemoWorkout.load()
    let incoming = try await store.receiveOffer(offer(workout), deviceID: "device")
    do { _ = try await store.apply(.complete(incoming.selected!)); Issue.record("Editor must stay locked") } catch { }
    let restarted = WorkoutStore(directory: dir)
    let request = try await restarted.prepareRequest(deviceID: "device")!
    #expect(request == incoming.sync?.pending)
    try await restarted.acknowledge(request, response: acknowledgement(version: 3))
    #expect(try await restarted.load()?.sync?.controlState == "watch")
}

@Test func immutableRetryAndLateEditsSurviveAck() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir), workout = try DemoWorkout.load()
    let incoming = try await store.receiveOffer(offer(workout), deviceID: "device")
    try await store.acknowledge(incoming.sync!.pending!, response: acknowledgement(version: 3))
    let location = incoming.selected!
    _ = try await store.apply(.field(location, "weight", "10"))
    let request = try await store.prepareRequest(deviceID: "device")!
    _ = try await store.apply(.field(location, "weight", "12,5"))
    #expect(try await store.prepareRequest(deviceID: "device") == request)
    #expect(try await WorkoutStore(directory: dir).prepareRequest(deviceID: "device") == request)
    try await store.acknowledge(request, response: acknowledgement(version: 4))
    let current = try await store.load()!
    #expect(current.workout.record(at: location)["weight"].string == "12,5")
    let next = try await store.prepareRequest(deviceID: "device")!
    #expect(next.operationID != request.operationID)
    #expect(next.body["baseVersion"].integer == 4)
    #expect(next.body["payload"] == current.workout.json)
}

@Test func releaseWaitsForLastSnapshotAndFreezesInput() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir), workout = try DemoWorkout.load()
    let incoming = try await store.receiveOffer(offer(workout), deviceID: "device")
    try await store.acknowledge(incoming.sync!.pending!, response: acknowledgement(version: 3))
    _ = try await store.apply(.field(incoming.selected!, "weight", "10"))
    _ = try await store.requestReturn()
    do { _ = try await store.apply(.skip(incoming.selected!)); Issue.record("Return must freeze input") } catch { }
    let write = try await store.prepareRequest(deviceID: "device")!
    #expect(write.method == "PUT")
    try await store.acknowledge(write, response: acknowledgement(version: 4))
    let release = try await store.prepareRequest(deviceID: "device")!
    #expect(release.path == "/watch/v1/control/release")
    try await store.acknowledge(release, response: acknowledgement(version: 5, epoch: 3, state: "phone"))
    #expect(try await store.load()?.sync?.controlState == "phone")
}

@Test func conflictKeepsBothSnapshotsAndRecoveryIsImmutable() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir), workout = try DemoWorkout.load()
    let incoming = try await store.receiveOffer(offer(workout), deviceID: "device")
    try await store.acknowledge(incoming.sync!.pending!, response: acknowledgement(version: 3))
    _ = try await store.apply(.field(incoming.selected!, "weight", "10"))
    let before = try await store.load()!
    let remote: JSONValue = .object(["error": .string("conflict"), "payload": workout.json])
    try await store.markConflict(remote)
    let after = try await WorkoutStore(directory: dir).load()!
    #expect(before.workout == after.workout && after.sync?.conflict == remote)
    let recovery = try await store.prepareRecovery()
    #expect(try await store.prepareRecovery() == recovery)
    try await store.acknowledgeRecovery(recovery)
    #expect(try await store.load()?.sync?.recovered == true)
}

@Test func demoNeverProducesServerWrites() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir)
    _ = try await store.beginDemo(DemoWorkout.load())
    #expect(try await store.prepareRequest(deviceID: "device") == nil)
    do { _ = try await store.prepareRecovery(); Issue.record("Demo must not be uploaded") } catch { }
}

private actor StaleAcceptance: WatchTransport {
    func send(_ request: WatchRequest) async throws -> JSONValue {
        if request.method == "GET" {
            return .object(["protocolVersion": .int(1), "contractVersion": .int(2), "session": .null])
        }
        return acknowledgement(version: 3)
    }
}

@Test func replayedAcceptanceCannotUnlockAfterForceReturn() async throws {
    let dir = temporary(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = WorkoutStore(directory: dir)
    let incoming = try await store.receiveOffer(offer(DemoWorkout.load()), deviceID: "device")
    do {
        _ = try await WatchSyncEngine(store: store).synchronize(using: StaleAcceptance(), deviceID: "device")
        Issue.record("Old acceptance receipt must not unlock editing")
    } catch let error as WatchHTTPError { #expect(error.status == 409) }
    let saved = try await store.load()!
    #expect(saved.sync?.controlState == "offered")
    #expect(saved.sync?.conflict != nil)
    #expect(saved.workout == incoming.workout)
    do { _ = try await store.apply(.skip(saved.selected!)); Issue.record("Conflicted editor must stay locked") } catch { }
}
