import Foundation
import Testing
@testable import WorkoutCore

@Test func healthPauseCannotBlockDifferentCompletedOrCorruptDiarySession() throws {
    let id = UUID().uuidString, now = Date()
    var journal = MeasurementJournal(id: id, startedAt: now)
    var control = MeasurementPauseState()
    try control.accept(MeasurementPauseCommand(sessionID: id, expectedRevision: 0, paused: true, now: now), sessionID: id, now: now)
    journal.pauseControl = control
    #expect(journal.blocksCompletion(of: id, actualPaused: false))
    #expect(!journal.blocksCompletion(of: UUID().uuidString, actualPaused: true))
    var saved = journal; try saved.saved(as: UUID())
    #expect(!saved.blocksCompletion(of: id, actualPaused: true))
    var closed = journal; try closed.closeWithoutSave(at: now)
    #expect(!closed.blocksCompletion(of: id, actualPaused: true))
    var corrupted = journal; corrupted.id = "broken"
    #expect(!corrupted.blocksCompletion(of: "broken", actualPaused: true))
    var mismatched = journal; mismatched.id = UUID().uuidString
    #expect(!mismatched.blocksCompletion(of: mismatched.id, actualPaused: true))
}

@Test func pauseRecoveryReplaysOnlyUnconfirmedIntentAndPreservesTerminalJournal() throws {
    let id = UUID().uuidString, now = Date()
    var journal = MeasurementJournal(id: id, startedAt: now)
    var control = MeasurementPauseState()
    try control.accept(MeasurementPauseCommand(sessionID: id, expectedRevision: 0, paused: true, now: now), sessionID: id, now: now)
    journal.pauseControl = control
    var restored = try JSONDecoder().decode(MeasurementJournal.self, from: JSONEncoder().encode(journal))
    try restored.validate()
    #expect(restored.pauseControl?.pendingDesiredState == true)
    restored.pauseControl?.confirm(paused: true)
    restored = try JSONDecoder().decode(MeasurementJournal.self, from: JSONEncoder().encode(restored))
    try restored.validate()
    #expect(restored.pauseControl?.pendingDesiredState == nil)
    restored.requestFinish(at: now.addingTimeInterval(60))
    #expect(restored.finishAction(phase: .paused, collectionStarted: true, busy: false) == .stopActivity)
    let saved = UUID(); try restored.saved(as: saved)
    #expect(restored.finishAction(phase: .paused, collectionStarted: true, busy: false) == .none)
    #expect(restored.savedID == saved)
}

@Test func corruptPauseJournalIsNotTreatedAsAnEmptyUnpausedState() throws {
    let id = UUID().uuidString
    for object: [String: Any] in [
        ["revision": -1, "paused": false],
        ["revision": 1, "paused": false],
        ["revision": 0, "paused": true],
        ["revision": 0, "paused": false, "appliedRevision": 1]
    ] {
        let data = try JSONSerialization.data(withJSONObject: object)
        let control = try JSONDecoder().decode(MeasurementPauseState.self, from: data)
        var journal = MeasurementJournal(id: id, startedAt: .now); journal.pauseControl = control
        #expect(throws: WorkoutError.self) { try journal.validate() }
    }
}

@Test func pauseCommandsAreIdempotentVersionedAndSurviveRestart() throws {
    let id = UUID().uuidString, now = Date()
    let pause = MeasurementPauseCommand(sessionID: id, expectedRevision: 0, paused: true, now: now)
    var state = MeasurementPauseState()
    #expect(try state.accept(pause, sessionID: id, now: now))
    #expect(state.paused && state.revision == 1 && state.appliedRevision == nil)
    state = try JSONDecoder().decode(MeasurementPauseState.self, from: JSONEncoder().encode(state))
    #expect(try !state.accept(pause, sessionID: id, now: now.addingTimeInterval(60)))
    state.confirm(paused: true)
    #expect(state.appliedRevision == 1)
    let resume = MeasurementPauseCommand(sessionID: id, expectedRevision: 1, paused: false, now: now)
    #expect(try state.accept(resume, sessionID: id, now: now))
    #expect(!state.paused && state.revision == 2 && state.appliedRevision == nil)
    #expect(throws: WorkoutError.self) { try state.accept(pause, sessionID: id, now: now) }
    #expect(!state.paused && state.revision == 2)
}

@Test func staleForeignAndExpiredPauseCommandsCannotChangeControl() throws {
    let id = UUID().uuidString, now = Date()
    var state = MeasurementPauseState()
    let pause = MeasurementPauseCommand(sessionID: id, expectedRevision: 0, paused: true, now: now)
    #expect(throws: WorkoutError.self) { try state.accept(pause, sessionID: UUID().uuidString, now: now) }
    #expect(throws: WorkoutError.self) { try state.accept(pause, sessionID: id, now: now.addingTimeInterval(31)) }
    #expect(throws: WorkoutError.self) { try state.accept(pause, sessionID: id, now: now.addingTimeInterval(-60)) }
    #expect(state.revision == 0 && !state.paused)
    let other = MeasurementPauseCommand(sessionID: id, expectedRevision: 0, paused: false, now: now)
    try state.accept(other, sessionID: id, now: now)
    #expect(throws: WorkoutError.self) { try state.accept(pause, sessionID: id, now: now) }
    state.confirm(paused: true)
    #expect(state.appliedRevision == nil)
}
