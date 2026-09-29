import Foundation
import HealthKit
import Observation
import WorkoutCore

/// No new workout sessions, write authorization or save paths.
/// Recovery only stops an unfinished session owned by our previous build.
@MainActor @Observable final class WatchHealth {
    static let shared = WatchHealth()
    var status = "TrainingLog не записывает данные в Apple Health"
    var busy = false
    var needsRecovery = false
    var pulse: Double? { nil }
    var pulseDate: Date? { nil }
    var activeID: String? { nil }
    var pauseSnapshot: JSONValue { .null }
    var onControlChange: (() -> Void)?
    private var loaded = false
    private let health = HKHealthStore()

    func pauseBlocksSets(sessionID: String) -> Bool { false }
    func applyPause(_ command: MeasurementPauseCommand) { onControlChange?() }
    func reconcile(_ state: WorkoutState?) async {
        guard state?.isDemo != true else { return }
        await load()
    }
    func load() async {
        guard !loaded else { return }
        loaded = true
        UserDefaults.standard.set(false, forKey: "healthRecordingEnabled")
        await recover()
    }
    func finish(at date: Date = Date()) async { await recover() }
    func recover() async {
        guard !busy else { return }
        busy = true
        defer { busy = false; onControlChange?() }
        do {
            // HealthKit only returns this application's active session.
            let session: HKWorkoutSession? = try await withCheckedThrowingContinuation { continuation in
                health.recoverActiveWorkoutSession { session, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: session) }
                }
            }
            if let session {
                session.associatedWorkoutBuilder().discardWorkout()
                session.end()
            }
            if var journal = try PrivateHealthFile.read("watch-workout.json", as: MeasurementJournal.self), journal.isPending {
                try journal.validate()
                try PrivateHealthFile.write(journal, name: "watch-read-only-\(journal.id).json")
                try journal.closeWithoutSave(at: max(Date(), journal.endedAt ?? journal.startedAt))
                try PrivateHealthFile.write(journal, name: "watch-workout.json")
            }
            needsRecovery = false
            status = "Запись в Apple Health отключена. Существующие записи не изменены."
        } catch {
            needsRecovery = true
            status = "Запись отключена. Не удалось закрыть прежнее измерение; повторите. Дневник доступен."
        }
    }
}
