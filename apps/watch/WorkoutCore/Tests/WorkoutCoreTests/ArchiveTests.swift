import Foundation
import Testing
@testable import WorkoutCore

@Test func archivedCalendarRestoresThroughDraftAndVersionedQueueWithoutCreatingWorkout() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Отдых"), "date": .string("2026-09-29"), "status": .string("planned"), "futureField": .string("keep")])
    let archive = LocalRecoveryArchive(id: "calendar", date: .now, payload: .object(["diary": .object(["calendar": .array([source])])]))
    #expect(archive.documents.count == 1 && archive.documents[0].kind == "calendar")
    let draft = try LibraryDraft.recover(kind: "calendar", payload: source, server: .null, generation: "g", directory: directory)
    #expect(draft.isNew && draft.baseVersion == 0 && draft.payload == source)
    #expect(try LibraryDraft.read(kind: "calendar", id: source["id"].string!, directory: directory) == draft)
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object(["programs": .array([]), "sessions": .array([]), "equipment": .array([])]), generation: "g")
    let state = try await store.saveDocument(kind: "calendar", payload: draft.payload, version: draft.baseVersion)
    #expect(state.sessions.isEmpty && state.calendar == [source])
    #expect(state.documentWrites?.first?.body["payload"] == source)
    #expect(state.documentWrites?.first?.body["baseVersion"] == .int(0))
    try LibraryDraft.clear(kind: "calendar", id: source["id"].string!, directory: directory)
    #expect(try LibraryDraft.read(kind: "calendar", id: source["id"].string!, directory: directory) == nil)
    #expect(try LocalRecoveryArchive.read(directory: directory).count == 1)
}

@Test func archivedDocumentsRetainDifferentVersionsAndPendingWrites() {
    let id = UUID().uuidString
    let first: JSONValue = .object(["id": .string(id), "name": .string("First")])
    var second = first; second["name"] = .string("Second")
    let archive = LocalRecoveryArchive(id: "test", date: .now, payload: .object([
        "diary": .object(["programs": .array([first]), "archivedPrograms": .array([first]),
            "documentWrites": .array([.object(["path": .string("/programs/\(id)"), "body": .object(["payload": second])])])])
    ]))
    #expect(archive.documents.map(\.payload) == [first, second])
}

@Test func archiveRestorationCreatesVersionedDraftAndPreservesBothSourcesWithoutOutbox() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Archived equipment"), "mode": .string("MachineStack"), "stepGrams": .int(2500), "availableGrams": .array([.int(7500), .int(10000)]), "future": .int(9)])
    var current = source; current["name"] = .string("Server version")
    let snapshot: JSONValue = .object(["version": .int(17), "payload": current])
    let draft = try LibraryDraft.recover(kind: "equipment", payload: source, server: snapshot, generation: "new-generation", directory: directory)
    #expect(draft.baseVersion == 17 && !draft.isNew && draft.generation == "new-generation")
    #expect(draft.payload == source && draft.fields["step"] == "2,5" && draft.fields["weights"] == "7,5; 10")
    #expect(try LibraryDraft.read(kind: "equipment", id: source["id"].string!, directory: directory) == draft)
    let archives = try LocalRecoveryArchive.read(directory: directory)
    #expect(archives.count == 1 && archives[0].documents.map(\.payload) == [source, current])
    #expect(throws: WorkoutError.self) { try LibraryDraft.recover(kind: "equipment", payload: source, server: snapshot, generation: "new-generation", directory: directory) }
    #expect(try LocalRecoveryArchive.read(directory: directory).count == 1)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("phone-diary.json").path))
}

@Test func localArchiveExtractsAllDifferentWorkoutVersionsWithoutDuplicatingIdenticalSnapshots() throws {
    let original = try DemoWorkout.load()
    var changed = original
    try changed.setField(changed.next!, field: "weight", value: "25")
    let payload: JSONValue = .object(["local": original.json, "source": changed.json,
        "diary": .object(["sessions": .array([.object(["workout": .object(["json": original.json])])])])])
    let archive = LocalRecoveryArchive(id: "test", date: .now, payload: payload)
    #expect(archive.workouts == [original, changed])
    #expect(archive.workouts[0].id == archive.workouts[1].id)
}

@Test func localArchiveListsCorruptionWithoutReadingLinksOrChangingFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try LocalRecoveryArchive.read(directory: directory).isEmpty)
    let folder = directory.appendingPathComponent("Recovery")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let document: JSONValue = .object(["kind": .string("document"), "futureField": .int(9)])
    let file = folder.appendingPathComponent("valid.json")
    let data = try JSONEncoder().encode(document)
    try data.write(to: file)
    try Data("broken".utf8).write(to: folder.appendingPathComponent("broken.json"))
    let outside = directory.appendingPathComponent("private.json")
    try Data("{\"mustNotRead\":true}".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.json"), withDestinationURL: outside)
    let copies = try LocalRecoveryArchive.read(directory: directory)
    #expect(copies.count == 3)
    #expect(copies.first { $0.id == "valid.json" }?.payload == document)
    #expect(copies.first { $0.id == "valid.json" }?.title == "Версии документа")
    #expect(copies.first { $0.id == "broken.json" }?.payload == nil)
    #expect(copies.first { $0.id == "link.json" }?.payload == nil)
    #expect(try Data(contentsOf: file) == data)
}
