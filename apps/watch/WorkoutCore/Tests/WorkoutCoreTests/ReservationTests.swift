import Foundation
import Testing
@testable import WorkoutCore

@Test func startedReservationGenerationReconciliationNeverMakesItOfflineStartable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = ReservationStore(directory: directory), workout = try DemoWorkout.load()
    var snapshot: JSONValue = .object(["reservationId": .string(workout.id), "payload": workout.json, "state": .string("started"), "phoneReady": .bool(true), "watchReady": .bool(true), "deviceId": .string("d"), "generation": .string("old"), "version": .int(4), "controlEpoch": .int(5), "protocolVersion": .int(1), "contractVersion": .int(2)])
    _ = try await cache.accept(snapshot)
    snapshot["generation"] = .string("new"); snapshot["state"] = .string("ready")
    await #expect(throws: WorkoutError.self) { try await cache.reconcileStartedGeneration(snapshot: snapshot, generation: "new") }
    snapshot["state"] = .string("started")
    let state = try await cache.reconcileStartedGeneration(snapshot: snapshot, generation: "new")
    #expect(state.pending == nil && !state.startRequested && state.confirmedWatchEpoch == nil)
    await #expect(throws: WorkoutError.self) { try await cache.requestStart() }
    #expect(try LocalRecoveryArchive.read(directory: directory).count == 1)
}

@Test func cancellationAcrossGenerationKeepsExactRequestAndRequiresNewEpoch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = ReservationStore(directory: directory), workout = try DemoWorkout.load()
    var snapshot: JSONValue = .object(["reservationId": .string(workout.id), "payload": workout.json, "state": .string("ready"), "phoneReady": .bool(true), "watchReady": .bool(true), "deviceId": .string("d"), "generation": .string("old"), "version": .int(3), "controlEpoch": .int(5), "protocolVersion": .int(1), "contractVersion": .int(2)])
    _ = try await cache.accept(snapshot)
    let prepared = try await cache.prepareGenerationCancellation(snapshot: snapshot, generation: "new")
    let request = prepared.pending!
    #expect(request.body["generation"] == .string("new"))
    await #expect(throws: WorkoutError.self) { try await cache.requestStart() }
    let restarted = ReservationStore(directory: directory)
    snapshot["state"] = .string("cancelled"); snapshot["generation"] = .string("new"); snapshot["version"] = .int(4)
    #expect(try await restarted.prepareGenerationCancellation(snapshot: snapshot, generation: "new").pending == request)
    await #expect(throws: WorkoutError.self) { try await restarted.acknowledgeGenerationCancellation(request, snapshot: snapshot) }
    #expect(try await restarted.load().pending == request)
    snapshot["controlEpoch"] = .int(6)
    let done = try await restarted.acknowledgeGenerationCancellation(request, snapshot: snapshot)
    #expect(done.pending == nil && done.recoveringGeneration == nil && !done.startRequested)
    #expect(done.snapshot == snapshot)
    #expect(try LocalRecoveryArchive.read(directory: directory).count == 1)
}

@Test func rejectedPreparationRequiresExplicitReconciliationAndKeepsArchive() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = ReservationStore(directory: directory)
    let request = WatchRequest(path: "/watch/reservation", method: "POST", body: .object(["operationId": .string(UUID().uuidString)]))
    _ = try await cache.prepare(request)
    await #expect(throws: WorkoutError.self) { try await cache.reconcileRejected(serverSnapshot: .null) }
    _ = try await cache.rejectPending()
    let reconciled = try await cache.reconcileRejected(serverSnapshot: .null)
    #expect(reconciled.pending == nil && !reconciled.blocked)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let archive = files.first { $0.lastPathComponent.hasPrefix("reservation-rejected-") }!
    #expect(try JSONDecoder().decode(ReservationState.self, from: Data(contentsOf: archive)).pending == request)
    try FileManager.default.removeItem(at: directory.appendingPathComponent("reservation.json"))
    await #expect(throws: WorkoutError.self) { try await cache.load() }
}

@Test func preparedReservationPersistsReceiptAndRejectsOldSnapshots() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workout = try DemoWorkout.load(), cache = ReservationStore(directory: directory)
    var snapshot: JSONValue = .object(["reservationId": .string(workout.id), "payload": workout.json, "state": .string("preparing"), "phoneReady": .bool(true), "watchReady": .bool(false), "deviceId": .string("d"), "generation": .string("g"), "version": .int(2), "controlEpoch": .int(5), "protocolVersion": .int(1), "contractVersion": .int(2)])
    _ = try await cache.accept(snapshot)
    await #expect(throws: WorkoutError.self) { try await cache.requestStart() }
    let request = ReservationStore.command(snapshot, path: "/watch/v1/reservation/ready")
    _ = try await cache.prepare(request)
    #expect(try await ReservationStore(directory: directory).load().pending == request)
    let old = snapshot
    snapshot["state"] = .string("ready"); snapshot["watchReady"] = .bool(true); snapshot["version"] = .int(3)
    _ = try await cache.acknowledge(request, snapshot: snapshot)
    _ = try await cache.confirmWatch(id: workout.id, epoch: 5)
    #expect(try await cache.accept(old).snapshot == snapshot)
    _ = try await cache.requestStart()
    let restored = try await ReservationStore(directory: directory).load()
    #expect(restored.startRequested && restored.confirmedWatchEpoch == 5)
    snapshot["state"] = .string("cancelled"); snapshot["controlEpoch"] = .int(6); snapshot["version"] = .int(4)
    _ = try await cache.accept(snapshot)
    await #expect(throws: WorkoutError.self) { try await cache.requestStart() }
    #expect(try await cache.accept(old).snapshot["state"].string == "cancelled")
}

@Test func offlineReservedStartIsDurableAndLaterEditsSurviveStartAck() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let workout = try DemoWorkout.load(), store = WorkoutStore(directory: directory)
    let reservation: JSONValue = .object(["reservationId": .string(workout.id), "payload": workout.json, "state": .string("ready"), "phoneReady": .bool(true), "watchReady": .bool(true), "deviceId": .string("d"), "generation": .string("g"), "version": .int(3), "controlEpoch": .int(5), "protocolVersion": .int(1), "contractVersion": .int(2)])
    var notReady = reservation; notReady["watchReady"] = .bool(false)
    await #expect(throws: WorkoutError.self) { try await store.startReserved(notReady, deviceID: "d") }
    #expect(try await store.load() == nil)
    let now = Date(timeIntervalSince1970: 1_790_664_000)
    let started = try await store.startReserved(reservation, deviceID: "d", now: now)
    #expect(started.workout.json["startedAt"].string == Workout.timestamp(now))
    #expect(started.sync?.baseVersion == 0)
    let request = try await store.prepareRequest(deviceID: "d")!
    #expect(request.path == "/watch/v1/reservation/start")
    #expect(try await WorkoutStore(directory: directory).prepareRequest(deviceID: "d") == request)
    let l = started.selected!
    _ = try await store.apply(.field(l, "weight", "12,5")); _ = try await store.apply(.field(l, "reps", "10")); _ = try await store.apply(.complete(l))
    let edited = try await store.load()!
    #expect(try await store.startReserved(reservation, deviceID: "d") == edited)
    #expect(try await store.prepareRequest(deviceID: "d") == request)
    try await store.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(1), "control": .object(["state": .string("watch"), "controlEpoch": .int(5)])]))
    let write = try await store.prepareRequest(deviceID: "d")!
    #expect(write.method == "PUT")
    #expect(write.body["baseVersion"].integer == 1)
    #expect(write.body["payload"] == edited.workout.json)
    try await store.markConflict(.object(["error": .string("reservation_changed")]))
    await #expect(throws: WorkoutError.self) { try await store.apply(.field(edited.selected!, "weight", "15")) }
    let recovery = try await store.prepareRecovery()
    #expect(recovery.body["payload"] == edited.workout.json)
}
