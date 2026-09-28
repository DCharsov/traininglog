import Foundation

/// Local-only recording lifecycle. Kept outside Session JSON, exports and server requests.
public struct MeasurementJournal: Codable, Equatable, Sendable {
    public var id: String
    public var startedAt: Date
    public private(set) var endedAt: Date?
    public private(set) var savedID: UUID?
    public private(set) var closedWithoutSaveAt: Date?
    public var pauseControl: MeasurementPauseState?
    public var isPending: Bool { savedID == nil && closedWithoutSaveAt == nil }
    public func blocksCompletion(of sessionID: String, actualPaused: Bool) -> Bool {
        // A broken health journal must stop new measurements, not the diary.
        guard (try? validate()) != nil, isPending, id == sessionID else { return false }
        return actualPaused || pauseControl?.pendingDesiredState == true
    }
    public private(set) var collectionEnded = false
    public init(id: String, startedAt: Date) { self.id = id; self.startedAt = startedAt }
    public mutating func requestFinish(at date: Date) {
        guard isPending, endedAt == nil else { return }
        endedAt = max(startedAt, date)
    }
    public mutating func endedCollection() throws {
        guard endedAt != nil else { throw WorkoutError("Завершение измерения ещё не записано.") }
        collectionEnded = true
    }
    public mutating func saved(as uuid: UUID) throws {
        guard closedWithoutSaveAt == nil else { throw WorkoutError("Попытка измерения уже закрыта без подтверждённого сохранения.") }
        if let savedID, savedID != uuid { throw WorkoutError("Другая запись HealthKit уже связана с тренировкой.") }
        savedID = uuid
    }
    /// Only after an explicit user choice and a fresh failed recovery attempt.
    /// The original journal must be archived before persisting this terminal state.
    public mutating func closeWithoutSave(at date: Date) throws {
        guard savedID == nil else { throw WorkoutError("Измерение уже сохранено в Apple Health.") }
        guard closedWithoutSaveAt == nil else { return }
        requestFinish(at: date)
        closedWithoutSaveAt = max(endedAt ?? startedAt, date)
    }
    public func validate() throws {
        try pauseControl?.validate(sessionID: id)
        guard UUID(uuidString: id) != nil, endedAt == nil || endedAt! >= startedAt,
              !collectionEnded || endedAt != nil,
              closedWithoutSaveAt == nil || (savedID == nil && endedAt != nil && closedWithoutSaveAt! >= endedAt!)
        else { throw WorkoutError("Повреждён журнал измерения; он не будет сброшен.") }
    }
}
