import Foundation

public struct MeasurementPauseCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let expectedRevision: Int64
    public let paused: Bool
    public let expiresAt: Date
    public init(sessionID: String, expectedRevision: Int64, paused: Bool, now: Date) {
        id = UUID(); self.sessionID = sessionID; self.expectedRevision = expectedRevision
        self.paused = paused; expiresAt = now.addingTimeInterval(30)
    }
}

/// Commands set a desired state; they never toggle it on receipt. Stored only locally.
public struct MeasurementPauseState: Codable, Equatable, Sendable {
    public private(set) var revision: Int64 = 0
    public private(set) var paused = false
    public private(set) var lastCommand: MeasurementPauseCommand?
    public private(set) var appliedRevision: Int64?
    public var pendingDesiredState: Bool? { lastCommand != nil && appliedRevision != revision ? paused : nil }
    public init() {}
    public func validate(sessionID: String) throws {
        guard revision >= 0, appliedRevision == nil || appliedRevision == revision else { throw WorkoutError("Повреждён журнал паузы.") }
        if let command = lastCommand {
            guard command.sessionID == sessionID, command.expectedRevision >= 0,
                  command.expectedRevision < Int64.max, revision == command.expectedRevision + 1,
                  command.paused == paused else { throw WorkoutError("Повреждена версия команды паузы.") }
        } else if revision != 0 || paused || appliedRevision != nil { throw WorkoutError("Нет команды для версии паузы.") }
    }
    @discardableResult public mutating func accept(_ command: MeasurementPauseCommand, sessionID: String, now: Date) throws -> Bool {
        try validate(sessionID: sessionID)
        guard command.sessionID == sessionID, UUID(uuidString: sessionID) != nil else { throw WorkoutError("Команда относится к другой тренировке.") }
        if lastCommand == command { return false }
        guard revision >= 0, revision < Int64.max, command.expectedRevision == revision,
              command.expiresAt >= now, command.expiresAt.timeIntervalSince(now) <= 30 else {
            throw WorkoutError("Состояние паузы изменилось или команда устарела. Обновите состояние часов.")
        }
        revision += 1; paused = command.paused; lastCommand = command; appliedRevision = nil
        return true
    }
    public mutating func confirm(paused actual: Bool) {
        if actual == paused { appliedRevision = revision }
    }
}
