import Foundation
import Testing
@testable import WorkoutCore

@Test func measurementFinishIntentSurvivesRestartAndNeverChangesOnRetry() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: start)
    #expect(throws: WorkoutError.self) { try journal.endedCollection() }
    journal.requestFinish(at: start.addingTimeInterval(60))
    var restored = try JSONDecoder().decode(MeasurementJournal.self, from: JSONEncoder().encode(journal))
    restored.requestFinish(at: start.addingTimeInterval(120))
    #expect(restored.endedAt == journal.endedAt)
    try restored.endedCollection(); try restored.endedCollection()
    let id = UUID(); try restored.saved(as: id); try restored.saved(as: id)
    #expect(throws: WorkoutError.self) { try restored.saved(as: UUID()) }
    #expect(restored.savedID == id)
    try restored.validate()
}

@Test func measurementJournalDecodesExistingFormatAndProtectsInvalidIdentity() throws {
    let data = try JSONEncoder().encode(MeasurementJournal(id: UUID().uuidString, startedAt: .now))
    let restored = try JSONDecoder().decode(MeasurementJournal.self, from: data)
    try restored.validate()
    var invalid = restored; invalid.id = "not-a-session"
    #expect(throws: WorkoutError.self) { try invalid.validate() }
    var reversed = restored; reversed.requestFinish(at: restored.startedAt.addingTimeInterval(-60))
    #expect(reversed.endedAt == restored.startedAt)
}

@Test func unrecoverableMeasurementClosesExplicitlyWithoutClaimingHealthSave() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: start)
    let original = journal
    try journal.closeWithoutSave(at: start.addingTimeInterval(60))
    #expect(!journal.isPending)
    #expect(journal.savedID == nil)
    #expect(journal.closedWithoutSaveAt == start.addingTimeInterval(60))
    #expect(original.isPending && original.endedAt == nil)
    let firstClose = journal
    try journal.closeWithoutSave(at: start.addingTimeInterval(120))
    journal.requestFinish(at: start.addingTimeInterval(180))
    #expect(journal == firstClose)
    #expect(throws: WorkoutError.self) { try journal.saved(as: UUID()) }
    let restored = try JSONDecoder().decode(MeasurementJournal.self, from: JSONEncoder().encode(journal))
    try restored.validate()
    #expect(restored == journal && !restored.isPending)
}

@Test func measurementClosureCannotReplaceSavedReceiptOrCreateInvalidTime() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var saved = MeasurementJournal(id: UUID().uuidString, startedAt: start)
    let savedID = UUID()
    try saved.saved(as: savedID)
    #expect(throws: WorkoutError.self) { try saved.closeWithoutSave(at: start) }
    #expect(saved.savedID == savedID && !saved.isPending)
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: start)
    journal.requestFinish(at: start.addingTimeInterval(60))
    try journal.closeWithoutSave(at: start.addingTimeInterval(-60))
    #expect(journal.closedWithoutSaveAt == start.addingTimeInterval(60))
    try journal.validate()
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as! [String: Any]
    json["savedID"] = UUID().uuidString
    let invalid = try JSONDecoder().decode(MeasurementJournal.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: WorkoutError.self) { try invalid.validate() }
}
