import Foundation
import Testing
@testable import WorkoutCore

@Test func libraryDraftKeepsIncompleteInputAndOriginalServerVersionAcrossRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID().uuidString
    let draft = LibraryDraft(kind: "equipment", isNew: false, baseVersion: 8, generation: "g", payload: .object(["id": .string(id), "name": .string(""), "future": .int(7)]), fields: ["step": "2,", "weights": "5; 7,"])
    try draft.write(directory: directory)
    #expect(try LibraryDraft.read(kind: "equipment", id: id, directory: directory) == draft)
    #expect(try LibraryDraft.list(directory: directory) == [draft])
    try LibraryDraft.clear(kind: "equipment", id: id, directory: directory)
    #expect(try LibraryDraft.list(directory: directory).isEmpty)
    #expect(try LibraryDraft.read(kind: "equipment", id: id, directory: directory) == nil)
}

@Test func corruptLibraryDraftCannotBeOverwrittenOrCleared() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID().uuidString
    let draft = LibraryDraft(kind: "programs", isNew: true, baseVersion: 0, generation: nil, payload: .object(["id": .string(id), "days": .array([])]))
    try draft.write(directory: directory)
    let file = directory.appendingPathComponent("LibraryDrafts/programs.\(id).json")
    let broken = Data("broken".utf8); try broken.write(to: file)
    #expect(throws: (any Error).self) { try draft.write(directory: directory) }
    #expect(throws: (any Error).self) { try LibraryDraft.clear(kind: "programs", id: id, directory: directory) }
    #expect(try Data(contentsOf: file) == broken)
    #expect(throws: WorkoutError.self) { try LibraryDraft.read(kind: "../PrivateHealth", id: id, directory: directory) }
}
