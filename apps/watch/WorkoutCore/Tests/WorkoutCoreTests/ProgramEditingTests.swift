import Foundation
import Testing
@testable import WorkoutCore

@Test func optionalExercisesRequireExplicitChoiceAndBecomeAnImmutableSessionSnapshot() throws {
    let demo = try DemoWorkout.load()
    var required = demo.exercises[0], optional = demo.exercises[0]
    required["optionalWeekly"] = .bool(false)
    optional["id"] = .string(UUID().uuidString); optional["optionalWeekly"] = .bool(true)
    let day: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("День"), "exercises": .array([required, optional])])
    let program: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("План"), "version": .int(1), "days": .array([day])])
    let usual = try PhoneDiary.makeWorkout(program: program, day: day)
    let expanded = try PhoneDiary.makeWorkout(program: program, day: day, includeOptional: true)
    #expect(usual.exercises.count == 1)
    #expect(expanded.exercises.count == 2)
    #expect(expanded.exercises[1]["optionalWeekly"].bool)
    #expect(expanded.exercises[1]["variantId"] == optional["variantId"])
    let snapshot = expanded.json
    optional["target"] = .string("Другая цель")
    #expect(expanded.json == snapshot)
    #expect(expanded.exercises.flatMap { $0["records"].array }.allSatisfy { $0["status"].string == "draft" && $0["completedAt"] == .null })
}

@Test func programArchiveSurvivesRestartAndPendingRestoreWinsOverOldExport() async throws {
    let demo = try DemoWorkout.load()
    let day: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("А"), "exercises": .array(demo.exercises)])
    let archived: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Архив"), "version": .int(1), "days": .array([day]), "archivedAt": .string(Workout.timestamp(.now)), "futureField": .string("keep")])
    var deleted = archived; deleted["id"] = .string(UUID().uuidString); deleted["deletedAt"] = .string(Workout.timestamp(.now))
    let export: JSONValue = .object(["programs": .array([archived, deleted]), "equipment": .array([]), "sessions": .array([])])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    let loaded = try await store.importServer(export, generation: "g")
    #expect(loaded.programs.isEmpty && loaded.archivedPrograms == [archived])
    await #expect(throws: WorkoutError.self) { try await store.start(program: archived, day: day) }
    var restored = archived; restored["archivedAt"] = .null; restored["version"] = .int(2)
    let queued = try await store.saveDocument(kind: "programs", payload: restored, version: 7)
    #expect(queued.archivedPrograms?.isEmpty == true && queued.programs == [restored])
    let reopened = PhoneDiary(directory: directory)
    let refreshed = try await reopened.importServer(export, generation: "g")
    #expect(refreshed.programs == [restored] && refreshed.archivedPrograms?.isEmpty == true)
    #expect(refreshed.documentWrites == queued.documentWrites)
    #expect(refreshed.programs[0]["futureField"].string == "keep")
    #expect(refreshed.sessions.isEmpty)
    let request = try #require(refreshed.documentWrites?.first)
    _ = try await reopened.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(8)]))
    let rearchived = try await reopened.saveDocument(kind: "programs", payload: archived, version: 8)
    #expect(rearchived.programs.isEmpty && rearchived.archivedPrograms == [archived])
    let disk = try await PhoneDiary(directory: directory).load()
    #expect(disk.archivedPrograms == [archived] && disk.documentWrites == rearchived.documentWrites)
}

@Test func oldPhoneDiaryWithoutArchiveFieldStillDecodes() throws {
    let data = try JSONEncoder().encode(PhoneDiaryState())
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json.removeValue(forKey: "archivedPrograms")
    let old = try JSONDecoder().decode(PhoneDiaryState.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.archivedPrograms == nil && old.programs.isEmpty)
}

@Test func archivingDayPreservesIdentityAndHistoryAndCopyIsUsable() async throws {
    let workout = try DemoWorkout.load()
    let day: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("А"), "exercises": .array(workout.exercises)])
    let archived = ProgramEditing.setDayArchived(day, archived: true)
    #expect(archived["id"] == day["id"] && archived["exercises"] == day["exercises"])
    #expect(archived["archivedAt"].string != nil)
    #expect(ProgramEditing.setDayArchived(archived, archived: false)["archivedAt"] == .null)
    #expect(ProgramEditing.copyDay(archived)["archivedAt"] == .null)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    await #expect(throws: WorkoutError.self) { try await store.start(program: .object([:]), day: archived) }
    #expect(try await store.load().sessions.isEmpty)
}

@Test func copiedDayRetainsComparisonIdentityAndNeverChangesActiveWorkout() throws {
    let demo = try DemoWorkout.load()
    let day: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("А"), "exercises": .array(demo.exercises), "futureField": .string("keep")])
    let program: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Программа"), "version": .int(4), "days": .array([day])])
    let active = try PhoneDiary.makeWorkout(program: program, day: day)
    let originalSnapshot = active.json
    var copy = ProgramEditing.copyDay(day)
    #expect(copy["id"] != day["id"])
    #expect(copy["name"].string == "А · копия")
    #expect(copy["futureField"] == day["futureField"])
    for (old, new) in zip(day["exercises"].array, copy["exercises"].array) {
        #expect(old["id"] != new["id"])
        for key in ["variantId", "equipmentId", "mode", "target", "supersetGroup", "unilateral", "tracking"] { #expect(old[key] == new[key]) }
    }
    copy["name"] = .string("Изменено")
    #expect(active.json == originalSnapshot)
    #expect(day["name"].string == "А")
}

@Test func copiedProgramRemovesSeedAndArchiveWithoutLosingUnknownFields() {
    let source: JSONValue = .object(["id": .string(UUID().uuidString), "version": .int(7), "name": .string("План"), "seedKey": .string("seed"), "archivedAt": .string("2026-09-01T00:00:00Z"), "future": .int(3), "days": .array([.object(["id": .string(UUID().uuidString), "name": .string("А"), "exercises": .array([])])])])
    let copied = ProgramEditing.copyProgram(source)
    #expect(copied["id"] != source["id"])
    #expect(copied["version"] == .int(1))
    #expect(!copied.contains("seedKey"))
    #expect(copied["archivedAt"] == .null && copied["deletedAt"] == .null)
    #expect(copied["future"] == .int(3))
    #expect(copied["days"].array[0]["name"].string == "А")
    #expect(copied["days"].array[0]["id"] != source["days"].array[0]["id"])
}
