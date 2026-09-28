import Foundation
import Testing
@testable import WorkoutCore

@Test func calendarUsesExistingContractAndKeepsOfflineChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object([:]), generation: "g")
    var entry: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Отдых"), "date": .string("2026-09-30"), "status": .string("planned"), "futureField": .string("preserve")])
    _ = try await store.saveDocument(kind: "calendar", payload: entry, version: 0)
    let request = try await store.prepareWrite()!
    #expect(request.path.hasPrefix("/calendar/"))
    #expect(request.body["payload"] == entry)
    #expect(try await PhoneDiary(directory: directory).prepareWrite() == request)
    _ = try await store.importServer(.object(["calendar": .array([])]), generation: "g")
    #expect(try await store.load().calendar == [entry])
    #expect(try await store.load().active == nil)
    _ = try await store.acknowledge(request, response: .object(["generation": .string("g"), "version": .int(1)]))
    entry["deletedAt"] = .string("2026-09-28T12:00:00Z")
    _ = try await store.saveDocument(kind: "calendar", payload: entry, version: 1)
    #expect(try await store.load().calendar?.isEmpty == true)
    #expect(try await store.prepareWrite()?.body["payload"]["futureField"].string == "preserve")
}

@Test func calendarRejectsInvalidDatesWithoutChangingDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object([:]), generation: "g")
    for date in ["2026-02-29", "2026-09-31", "2026-1-2", "bad"] {
        let entry: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Отдых"), "date": .string(date), "status": .string("planned")])
        await #expect(throws: WorkoutError.self) { try await store.saveDocument(kind: "calendar", payload: entry, version: 0) }
    }
    #expect(try await store.prepareWrite() == nil)
    #expect(try await PhoneDiary(directory: directory).load().calendar?.isEmpty == true)
}
