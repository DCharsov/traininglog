import Foundation
import Testing
@testable import WorkoutCore

private func phoneProgram() throws -> (JSONValue, JSONValue) {
    let demo = try DemoWorkout.load()
    let day: JSONValue = .object(["id": demo.json["dayId"], "name": .string("Тест iPhone"), "exercises": demo.json["exercises"]])
    return (.object(["id": demo.json["programId"], "version": .int(1), "name": .string("Программа"), "days": .array([day])]), day)
}
private func phoneExport(_ program: JSONValue) -> JSONValue { .object(["programs": .array([program]), "sessions": .array([]), "equipment": .array([])]) }

@Test func programEditsKeepImmutableOutboxAndDoNotChangeActiveWorkout() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (original, day) = try phoneProgram()
    _ = try await store.importServer(phoneExport(original), generation: "g")
    let active = try await store.start(program: original, day: day).active!
    var changed = original; changed["name"] = .string("Новое название")
    let saved = try await store.saveDocument(kind: "programs", payload: changed, version: 1)
    #expect(saved.active == active)
    let request = try await store.prepareWrite()!
    #expect(request.path.hasPrefix("/programs/"))
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == request)
    let refreshed = try await store.importServer(phoneExport(original), generation: "g")
    #expect(refreshed.programs.first?["name"].string == "Новое название")
    _ = try await store.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(2)]))
    #expect(try await store.load().documentWrites?.isEmpty == true)
}

@Test func rejectedDocumentDoesNotBlockWorkoutQueueOrLoseCopy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (original, day) = try phoneProgram()
    _ = try await store.importServer(phoneExport(original), generation: "g")
    _ = try await store.saveDocument(kind: "programs", payload: original, version: 1)
    let request = try await store.prepareWrite()!
    _ = try await store.markConflict(request, response: .object(["error": .string("conflict")]))
    _ = try await store.start(program: original, day: day)
    #expect(try await store.prepareWrite()?.path.hasPrefix("/sessions/") == true)
    #expect(try await store.load().documentWrites?.first == request)
}

@Test func nativeEditorCommitsAtomicallyAndIgnoresDuplicateCompletion() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (program, day) = try phoneProgram()
    let row = try await store.start(program: program, day: day).active!
    let values = ["weight": "12,5", "reps": "10", "rir": "2", "note": "Тест"]
    let saved = try await store.saveSet(id: row.id, location: row.selected!, values: values, complete: true)
    #expect(saved.active!.workout.json["revision"].integer == 2)
    #expect(saved.active!.workout.record(at: row.selected!)["status"].string == "completed")
    #expect(saved.active!.workout.record(at: saved.active!.selected!)["weight"].string == "12,5")
    let repeated = try await store.saveSet(id: row.id, location: row.selected!, values: values, complete: true)
    #expect(repeated.active == saved.active)
    #expect(try await PhoneDiary(directory: directory).load().active == saved.active)
}

@Test func nativeInvalidEditorDoesNotPartiallyOverwriteDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (program, day) = try phoneProgram()
    let row = try await store.start(program: program, day: day).active!
    do {
        _ = try await store.saveSet(id: row.id, location: row.selected!, values: ["weight": "25", "reps": "wrong"], complete: true)
        Issue.record("Invalid completion must fail")
    } catch { }
    #expect(try await store.load().active == row)
    #expect(try await PhoneDiary(directory: directory).load().active == row)
}

@Test func nativePhoneBuildsFreshWorkoutWithoutHistoricalResults() throws {
    let (program, day) = try phoneProgram()
    let workout = try PhoneDiary.makeWorkout(program: program, day: day)
    #expect(workout.active && workout.json["revision"].integer == 1)
    #expect(workout.exercises.count == day["exercises"].array.count)
    #expect(workout.sequence.allSatisfy { workout.record(at: $0)["status"].string == "draft" && workout.record(at: $0)["completedAt"] == .null })
    #expect(Set(workout.sequence.map(\.setID)).count == workout.sequence.count)
    for exercise in workout.exercises { #expect(exercise["rest"].integer == RestRules.seconds(exercise)) }
}

@Test func nativePhoneDiskRetryAndNewEditsSurviveServerAck() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (program, day) = try phoneProgram()
    _ = try await store.importServer(phoneExport(program), generation: "g")
    let row = try await store.start(program: program, day: day).active!
    let first = try await store.prepareWrite()!
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == first)
    _ = try await store.apply(id: row.id, action: .field(row.selected!, "weight", "12,5"))
    _ = try await store.acknowledge(first, response: .object(["version": .int(1), "generation": .string("g")]))
    let pending = try await store.prepareWrite()!
    #expect(pending.operationID != first.operationID)
    #expect(pending.body["baseVersion"].integer == 1)
    #expect(pending.body["payload"]["exercises"].array[0]["records"].array[0]["weight"].string == "12,5")
}

@Test func nativePhoneHandoffFreezesEditingAndArchivesConflict() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (program, day) = try phoneProgram()
    _ = try await store.importServer(phoneExport(program), generation: "g")
    let row = try await store.start(program: program, day: day).active!
    let first = try await store.prepareWrite()!
    _ = try await store.acknowledge(first, response: .object(["version": .int(1), "generation": .string("g")]))
    let handoff = try await store.prepareHandoff(id: row.id, deviceID: "device")
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == handoff)
    do { _ = try await store.apply(id: row.id, action: .skip(row.selected!)); Issue.record("Phone must be locked during handoff") } catch { }
    let snapshot: JSONValue = .object(["generation": .string("g"), "version": .int(2), "sessionId": .string(row.id), "payload": row.workout.json, "control": .object(["state": .string("watch"), "controlEpoch": .int(2)])])
    let owned = try await store.acknowledgeHandoff(handoff, snapshot: snapshot)
    #expect(owned.active?.editable == false && owned.active?.pending == nil)
    var returned = snapshot; returned["version"] = .int(3); returned["control"]["state"] = .string("phone")
    let phone = try await store.acceptSnapshot(returned)
    #expect(phone.active?.editable == true && phone.active?.watchRequested == true)
}

@Test func nativePhoneKeepsBothCopiesOnRemoteConflictAndRejectsGenerationReset() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory); let (program, day) = try phoneProgram()
    _ = try await store.importServer(phoneExport(program), generation: "g")
    let row = try await store.start(program: program, day: day).active!
    let request = try await store.prepareWrite()!
    _ = try await store.acknowledge(request, response: .object(["version": .int(1), "generation": .string("g")]))
    _ = try await store.apply(id: row.id, action: .field(row.selected!, "weight", "10"))
    var remote = row.workout; try remote.setField(row.selected!, field: "weight", value: "20")
    let result = try await store.acceptSnapshot(.object(["generation": .string("g"), "version": .int(2), "sessionId": .string(row.id), "payload": remote.json, "control": .object(["state": .string("phone"), "controlEpoch": .int(0)])]))
    #expect(result.active?.conflict != nil)
    #expect(result.active?.workout.record(at: row.selected!)["weight"].string == "10")
    #expect(try await store.prepareWrite() == nil)
    do { _ = try await store.importServer(phoneExport(program), generation: "new"); Issue.record("Generation reset cannot silently overwrite local data") } catch { }
}
