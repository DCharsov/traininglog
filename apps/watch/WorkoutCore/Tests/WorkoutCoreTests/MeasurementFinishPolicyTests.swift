import Foundation
import Testing
@testable import WorkoutCore

@Test func measurementFinishNeverTouchesSystemBeforeDurableIntentOrWhileBusy() throws {
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: .now)
    let phases: [MeasurementSessionPhase] = [.absent, .notStarted, .prepared, .running, .paused, .stopped, .ended, .unknown]
    for phase in phases {
        #expect(journal.finishAction(phase: phase, collectionStarted: true, busy: false) == .persistIntent)
        #expect(journal.finishAction(phase: phase, collectionStarted: false, busy: true) == .persistIntent)
    }
    journal.requestFinish(at: .now)
    for phase in phases {
        #expect(journal.finishAction(phase: phase, collectionStarted: true, busy: true) == .wait)
    }
    try journal.saved(as: UUID())
    for phase in phases {
        #expect(journal.finishAction(phase: phase, collectionStarted: true, busy: false) == .none)
    }
}

@Test func measurementFinishStopsBeforeSaveAndRetainsFailedCollectionForRetry() throws {
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: .now)
    journal.requestFinish(at: .now)
    for phase: MeasurementSessionPhase in [.running, .paused] {
        #expect(journal.finishAction(phase: phase, collectionStarted: true, busy: false) == .stopActivity)
    }
    for phase: MeasurementSessionPhase in [.stopped, .ended] {
        #expect(journal.finishAction(phase: phase, collectionStarted: true, busy: false) == .saveCollection)
        // A failed endCollection/finishWorkout leaves the same durable intent.
        let restored = try JSONDecoder().decode(MeasurementJournal.self, from: JSONEncoder().encode(journal))
        #expect(restored.finishAction(phase: phase, collectionStarted: true, busy: false) == .saveCollection)
    }
    #expect(journal.finishAction(phase: .absent, collectionStarted: false, busy: false) == .recover)
    #expect(journal.finishAction(phase: .unknown, collectionStarted: true, busy: false) == .wait)
}

@Test func failedMeasurementStartupDoesNotAttemptToSaveAnUnstartedBuilder() throws {
    var journal = MeasurementJournal(id: UUID().uuidString, startedAt: .now)
    journal.requestFinish(at: .now)
    for phase: MeasurementSessionPhase in [.notStarted, .prepared, .ended] {
        #expect(journal.finishAction(phase: phase, collectionStarted: false, busy: false) == .releaseUnstartedRuntime)
    }
    #expect(journal.finishAction(phase: .stopped, collectionStarted: false, busy: false) == .endSession)
    #expect(journal.finishAction(phase: .running, collectionStarted: false, busy: false) == .stopActivity)
    #expect(journal.finishAction(phase: .notStarted, collectionStarted: true, busy: false) == .endSession)
    try journal.closeWithoutSave(at: .now)
    #expect(journal.finishAction(phase: .absent, collectionStarted: false, busy: false) == .none)
}
