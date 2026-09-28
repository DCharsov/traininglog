import Foundation
import Testing
@testable import WorkoutCore

@Test func documentConflictResolutionArchivesBothVersionsAndQueuesNewImmutableOperation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object([:]), generation: "g")
    let local: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Локальное"), "mode": .string("MachineStack"), "future": .int(7)])
    _ = try await store.saveDocument(kind: "equipment", payload: local, version: 2)
    let request = try await store.prepareWrite()!
    _ = try await store.markConflict(request, response: .object(["error": .string("conflict")]))
    var server = local; server["name"] = .string("Серверное")
    let snapshot: JSONValue = .object(["version": .int(4), "payload": server])
    await #expect(throws: WorkoutError.self) { try await store.resolveDocument(request, snapshot: snapshot, generation: "wrong", useLocal: true) }
    #expect(try await store.load().documentWrites == [request])
    _ = try await store.resolveDocument(request, snapshot: snapshot, generation: "g", useLocal: true)
    let replacement = try await store.prepareWrite()!
    #expect(replacement.operationID != request.operationID)
    #expect(replacement.body["baseVersion"] == .int(4))
    #expect(replacement.body["payload"] == local)
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == replacement)
    let archives = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
    #expect(archives.count == 1)
    let archive = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: archives[0]))
    #expect(archive["request"] == request.body && archive["server"] == snapshot)
    _ = try await store.markConflict(replacement, response: .object(["error": .string("conflict")]))
    _ = try await store.resolveDocument(replacement, snapshot: snapshot, generation: "g", useLocal: false)
    #expect(try await store.prepareWrite() == nil)
    #expect(try await store.load().equipment == [server])
    #expect(try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil).count == 2)
}
