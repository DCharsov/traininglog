import Foundation

public struct WorkoutState: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var workout: Workout
    public var selected: SetLocation?
    public var localRevision: Int64 = 0
    public var isDemo: Bool
    public var sync: SyncContext?
    public init(workout: Workout, isDemo: Bool) { self.workout = workout; self.selected = workout.next; self.isDemo = isDemo }
}

public enum WorkoutAction: Sendable {
    case field(SetLocation, String, String)
    case complete(SetLocation)
    case skip(SetLocation)
    case correct(SetLocation)
    case select(SetLocation)
    case rest(Int64?)
    case finish
}

/// Disk writes happen before publishing state. No awaits within a read/modify/write transaction.
public actor WorkoutStore {
    let file: URL
    private let backup: URL
    var state: WorkoutState?
    private var loaded = false
    public init(directory: URL) {
        file = directory.appendingPathComponent("workout-state.json")
        backup = directory.appendingPathComponent("workout-state.previous.json")
    }
    public func load() throws -> WorkoutState? {
        if loaded { return state }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let decoded = try Self.decode(Data(contentsOf: file))
                state = decoded
            } catch {
                throw WorkoutError("Не удалось прочитать тренировку. Файл и резервная копия сохранены; требуется восстановление. \(error.localizedDescription)")
            }
        } else if FileManager.default.fileExists(atPath: backup.path) {
            throw WorkoutError("Основной файл отсутствует, но есть резервная копия. Требуется явное восстановление.")
        }
        loaded = true
        return state
    }
    private static func decode(_ data: Data) throws -> WorkoutState {
        let decoded = try JSONDecoder().decode(WorkoutState.self, from: data)
        guard decoded.formatVersion == 1 else { throw WorkoutError("Неизвестная версия локального файла.") }
        try decoded.workout.validateCompatibility()
        if let selected = decoded.selected, !decoded.workout.sequence.contains(selected) { throw WorkoutError("Повреждён выбор подхода.") }
        return decoded
    }
    func persist(_ next: WorkoutState) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        _ = try Self.decode(data)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try Self.decode(old) // Never replace a good backup with a corrupt primary.
            try old.write(to: backup, options: .atomic)
        }
        try data.write(to: file, options: .atomic)
        state = next
    }
    public func beginDemo(_ workout: Workout) throws -> WorkoutState {
        _ = try load()
        guard state == nil else { throw WorkoutError("Сохранённая тренировка уже существует. Она не будет заменена.") }
        var next = WorkoutState(workout: workout, isDemo: true)
        if let selected = next.selected { try next.workout.autofill(selected) }
        try persist(next)
        return next
    }
    public func apply(_ action: WorkoutAction, now: Date = Date()) throws -> WorkoutState {
        _ = try load()
        guard var next = state else { throw WorkoutError("Нет загруженной тренировки.") }
        if !next.isDemo {
            guard let sync = next.sync, sync.controlState == "watch", !sync.returning, sync.conflict == nil else {
                throw WorkoutError("Редактирование недоступно: требуется подтверждённое управление часами.")
            }
        }
        let previous = next.workout
        switch action {
        case .field(let location, let field, let value): try next.workout.setField(location, field: field, value: value)
        case .complete(let location):
            guard try next.workout.complete(location, now: now) else { return next }
            next.selected = next.workout.next
        case .skip(let location): try next.workout.skip(location); next.selected = next.workout.next
        case .correct(let location): try next.workout.correct(location); next.selected = location
        case .select(let location):
            guard next.workout.sequence.contains(location), next.workout.record(at: location)["status"].string == "draft" else { throw WorkoutError("Выберите незавершённый подход.") }
            next.selected = location
        case .rest(let seconds): try next.workout.changeRest(seconds: seconds, now: now)
        case .finish: try next.workout.finish(now: now); next.selected = nil
        }
        // Field editing must not refill deliberately cleared input.
        switch action {
        case .complete, .skip, .select:
            if let selected = next.selected { try next.workout.autofill(selected) }
        default: break
        }
        if previous != next.workout { next.workout.incrementRevision(); next.localRevision += 1 }
        try persist(next)
        return next
    }
}
