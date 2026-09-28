import Foundation

public struct ReservationState: Codable, Sendable {
    public var formatVersion = 1
    public var snapshot: JSONValue = .null
    public var pending: WatchRequest?
    public var startRequested = false
    public var blocked = false
    public var confirmedWatchEpoch: Int64?
    public var recoveringGeneration: String?
    public init() {}
}
public actor ReservationStore {
    private let file: URL
    public init(directory: URL) { file = directory.appendingPathComponent("reservation.json") }
    public func load() throws -> ReservationState {
        guard FileManager.default.fileExists(atPath: file.path) else {
            guard !FileManager.default.fileExists(atPath: file.appendingPathExtension("previous").path) else { throw WorkoutError("Основной файл резерва отсутствует. Резервная копия сохранена; требуется восстановление.") }
            return ReservationState()
        }
        let value = try JSONDecoder().decode(ReservationState.self, from: Data(contentsOf: file))
        guard value.formatVersion == 1 else { throw WorkoutError("Неизвестный формат резерва. Файл сохранён.") }
        if value.snapshot != .null { try Self.validate(value.snapshot) }
        return value
    }
    private static func validate(_ snapshot: JSONValue) throws {
        guard snapshot["protocolVersion"].integer == 1, snapshot["contractVersion"].integer == 2,
              ["preparing", "ready", "started", "cancelled", "completed"].contains(snapshot["state"].string ?? ""),
              (snapshot["version"].integer ?? 0) > 0, (snapshot["controlEpoch"].integer ?? 0) > 0,
              snapshot["generation"].string != nil, snapshot["deviceId"].string != nil else { throw WorkoutError("Неподдерживаемый резерв тренировки.") }
        let workout = try Workout(json: snapshot["payload"])
        guard snapshot["reservationId"].string == workout.id else { throw WorkoutError("Неверный UUID резерва.") }
    }
    private func persist(_ value: ReservationState) throws -> ReservationState {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try load()
            try Data(contentsOf: file).write(to: file.appendingPathExtension("previous"), options: .atomic)
        }
        try JSONEncoder().encode(value).write(to: file, options: .atomic); return value
    }
    public func accept(_ snapshot: JSONValue) throws -> ReservationState {
        var value = try load(); try Self.validate(snapshot)
        if value.snapshot != .null {
            guard value.snapshot["generation"] == snapshot["generation"] else { throw WorkoutError("Сервер восстановлен из другой версии. Локальный резерв сохранён; требуется сверка.") }
            guard (snapshot["version"].integer ?? 0) >= (value.snapshot["version"].integer ?? 0),
                  (snapshot["controlEpoch"].integer ?? 0) >= (value.snapshot["controlEpoch"].integer ?? 0) else { return value }
            if snapshot["version"] == value.snapshot["version"], snapshot != value.snapshot { throw WorkoutError("Разные снимки одной версии резерва. Обновите данные.") }
            if value.snapshot["reservationId"] == snapshot["reservationId"] {
                guard (snapshot["version"].integer ?? 0) >= (value.snapshot["version"].integer ?? 0) else { return value }
            } else {
                let archive = file.deletingLastPathComponent().appendingPathComponent("reservation-archive-" + UUID().uuidString + ".json")
                try JSONEncoder().encode(value).write(to: archive, options: .atomic)
                value.startRequested = false
                value.confirmedWatchEpoch = nil
            }
        }
        value.snapshot = snapshot
        return try persist(value)
    }
    public func prepare(_ request: WatchRequest) throws -> ReservationState {
        var value = try load()
        guard value.pending == nil else { throw WorkoutError("Предыдущий запрос резерва ещё ожидает подтверждения.") }
        value.pending = request; value.blocked = false; return try persist(value)
    }
    public func acknowledge(_ request: WatchRequest, snapshot: JSONValue) throws -> ReservationState {
        guard try load().pending == request else { throw WorkoutError("Неизвестное подтверждение резерва.") }
        var value = try accept(snapshot); value.pending = nil; return try persist(value)
    }
    public func rejectPending() throws -> ReservationState {
        var value = try load(); value.blocked = true
        // Preserve rejected request; explicit refresh must reconcile it, never generate duplicate creates.
        return try persist(value)
    }
    public func requestStart() throws -> ReservationState {
        var value = try load()
        guard !value.blocked, value.pending == nil, value.recoveringGeneration == nil, value.snapshot["state"].string == "ready", value.snapshot["phoneReady"].bool, value.snapshot["watchReady"].bool else { throw WorkoutError("Резерв ещё не готов.") }
        value.startRequested = true; return try persist(value)
    }
    /// Explicit user action after a rejected (not merely timed out) operation and a fresh server read.
    public func reconcileRejected(serverSnapshot: JSONValue) throws -> ReservationState {
        let old = try load()
        guard old.blocked else { throw WorkoutError("Запрос ещё может быть в пути. Дождитесь ответа или повторите отправку.") }
        if serverSnapshot != .null { try Self.validate(serverSnapshot) }
        let archive = file.deletingLastPathComponent().appendingPathComponent("reservation-rejected-" + UUID().uuidString + ".json")
        try JSONEncoder().encode(old).write(to: archive, options: .atomic)
        var next = ReservationState(); next.snapshot = serverSnapshot
        return try persist(next)
    }
    public func confirmWatch(id: String, epoch: Int64) throws -> ReservationState {
        var value = try load()
        guard value.snapshot["reservationId"].string == id, value.snapshot["controlEpoch"].integer == epoch, value.snapshot["state"].string == "ready" else { return value }
        value.confirmedWatchEpoch = epoch; return try persist(value)
    }
    public static func command(_ snapshot: JSONValue, path: String) -> WatchRequest {
        WatchRequest(path: path, method: "POST", body: .object(["operationId": .string(UUID().uuidString), "generation": snapshot["generation"], "reservationId": snapshot["reservationId"], "version": snapshot["version"], "controlEpoch": snapshot["controlEpoch"]]))
    }
    public func prepareGenerationCancellation(snapshot: JSONValue, generation: String) throws -> ReservationState {
        let old = try load()
        if old.recoveringGeneration == generation, old.pending != nil { return old }
        try Self.validate(snapshot)
        guard !generation.isEmpty, snapshot["generation"].string != generation,
              ["preparing", "ready"].contains(snapshot["state"].string ?? "") else { throw WorkoutError("Нет неподтверждённого резерва старого поколения для отмены.") }
        let archive: JSONValue = .object(["kind": .string("reservation"), "server": snapshot,
            "previous": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(old))])
        let folder = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: folder.appendingPathComponent("reservation-\(UUID().uuidString).json"), options: .atomic)
        var value = ReservationState(); value.snapshot = snapshot; value.recoveringGeneration = generation
        var request = Self.command(snapshot, path: "/watch/reservation/force-cancel")
        request.body["generation"] = .string(generation); value.pending = request
        return try persist(value)
    }
    /// After the user adopted a restored diary, a started session uses the normal server lease.
    /// This only updates a non-startable reservation; it never grants offline editing authority.
    public func reconcileStartedGeneration(snapshot: JSONValue, generation: String) throws -> ReservationState {
        let old = try load(); try Self.validate(snapshot)
        guard old.pending == nil, old.snapshot["generation"].string != generation, snapshot["generation"].string == generation,
              old.snapshot["reservationId"] == snapshot["reservationId"],
              ["started", "completed"].contains(old.snapshot["state"].string ?? ""),
              ["started", "completed"].contains(snapshot["state"].string ?? "") else { throw WorkoutError("Нельзя автоматически заменить подготовленный резерв.") }
        let folder = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: folder.appendingPathComponent("reservation-generation-\(UUID().uuidString).json"), options: .atomic)
        var next = ReservationState(); next.snapshot = snapshot
        return try persist(next)
    }
    public func acknowledgeGenerationCancellation(_ request: WatchRequest, snapshot: JSONValue) throws -> ReservationState {
        let old = try load(); try Self.validate(snapshot)
        guard old.pending == request, old.recoveringGeneration == snapshot["generation"].string,
              snapshot["state"].string == "cancelled", snapshot["reservationId"] == request.body["reservationId"],
              (snapshot["version"].integer ?? 0) > (request.body["version"].integer ?? 0),
              (snapshot["controlEpoch"].integer ?? 0) > (request.body["controlEpoch"].integer ?? 0) else { throw WorkoutError("Отмена не подтверждена. Запрос сохранён для повтора.") }
        var next = ReservationState(); next.snapshot = snapshot
        return try persist(next)
    }
}
