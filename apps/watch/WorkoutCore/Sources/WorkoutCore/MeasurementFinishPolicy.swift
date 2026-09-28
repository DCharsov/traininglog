import Foundation

/// Platform-independent decisions; the adapter performs only the selected effect.
/// No sensor samples or health summaries belong in the synchronized workout model.
public enum MeasurementSessionPhase: Sendable {
    case absent, notStarted, prepared, running, paused, stopped, ended, unknown
}

public enum MeasurementFinishAction: Equatable, Sendable {
    case none, persistIntent, wait, recover, stopActivity, saveCollection, endSession, releaseUnstartedRuntime
}

public extension MeasurementJournal {
    func finishAction(phase: MeasurementSessionPhase, collectionStarted: Bool, busy: Bool) -> MeasurementFinishAction {
        guard isPending else { return .none }
        guard endedAt != nil else { return .persistIntent }
        guard !busy else { return .wait }
        switch phase {
        case .absent: return .recover
        case .running, .paused: return .stopActivity
        case .stopped: return collectionStarted ? .saveCollection : .endSession
        case .ended: return collectionStarted ? .saveCollection : .releaseUnstartedRuntime
        case .notStarted, .prepared: return collectionStarted ? .endSession : .releaseUnstartedRuntime
        case .unknown: return .wait
        }
    }
}
