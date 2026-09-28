import Foundation

public struct WatchRequest: Codable, Equatable, Sendable {
    public var path: String
    public var method: String
    public var body: JSONValue
    public var revision: Int64
    public var operationID: String { body["operationId"].string ?? "" }
    public init(path: String, method: String, body: JSONValue, revision: Int64 = 0) {
        self.path = path; self.method = method; self.body = body; self.revision = revision
    }
}
public struct SyncContext: Codable, Equatable, Sendable {
    public var generation: String
    public var baseVersion: Int64
    public var controlEpoch: Int64
    public var controlState: String
    public var deviceID: String
    public var basePayload: JSONValue
    public var pending: WatchRequest?
    public var returning = false
    public var conflict: JSONValue?
    public var recovery: WatchRequest?
    public var recovered = false
    public var lastSyncedAt: Int64?
}
public struct WatchHTTPError: LocalizedError, Sendable {
    public let status: Int
    public let response: JSONValue
    public let retryAfter: Double?
    public init(status: Int, response: JSONValue, retryAfter: Double? = nil) { self.status = status; self.response = response; self.retryAfter = retryAfter }
    public var errorDescription: String? {
        switch status {
        case 401, 403: return "Нужно восстановить подключение. Записи сохранены на часах."
        case 409: return "Управление или серверная версия изменились. Локальная копия сохранена."
        case 426: return "Обновите приложение: несовместимая версия протокола."
        case 429: return "Слишком много запросов. Записи сохранены; повторим позже."
        default: return "Ошибка сервера (\(status)). Записи сохранены на часах."
        }
    }
}
public protocol WatchTransport: Sendable {
    func send(_ request: WatchRequest) async throws -> JSONValue
}

public actor WatchSyncEngine {
    private let store: WorkoutStore
    private var running = false
    public init(store: WorkoutStore) { self.store = store }
    public func receive(using transport: any WatchTransport, deviceID: String) async throws -> WorkoutState? {
        guard !running else { return try await store.load() }
        running = true
        defer { running = false }
        let response = try await transport.send(WatchRequest(path: "/watch/v1/session", method: "GET", body: .null))
        guard response["protocolVersion"].integer == 1, response["contractVersion"].integer == 2 else { throw WorkoutError("Несовместимый протокол часов.") }
        if response["session"] == .null { return try await store.load() }
        return try await store.receiveOffer(response["session"], deviceID: deviceID)
    }
    public func synchronize(using transport: any WatchTransport, deviceID: String) async throws -> WorkoutState? {
        guard !running else { return try await store.load() }
        running = true
        defer { running = false }
        // Bounded loop; edits arriving during a request are preserved for the next snapshot.
        for _ in 0..<4 {
            guard let request = try await store.prepareRequest(deviceID: deviceID) else { break }
            do {
                let response = try await transport.send(request)
                if request.path == "/watch/v1/handoff/accept" || request.path == "/watch/v1/reservation/start" {
                    let current = try await transport.send(WatchRequest(path: "/watch/v1/session", method: "GET", body: .null))
                    let control = current["session"]["control"]
                    let expectedID = request.path == "/watch/v1/reservation/start" ? request.body["reservationId"].string : request.body["sessionId"].string
                    guard current["session"]["sessionId"].string == expectedID,
                          control["state"].string == "watch", control["deviceId"].string == deviceID,
                          control["controlEpoch"] == response["control"]["controlEpoch"] else {
                        throw WatchHTTPError(status: 409, response: .object(["error": .string("control_changed")]))
                    }
                }
                try await store.acknowledge(request, response: response)
            } catch let error as WatchHTTPError {
                if [409, 426].contains(error.status) { try await store.markConflict(error.response) }
                throw error
            }
        }
        return try await store.load()
    }
    public func uploadRecovery(using transport: any WatchTransport) async throws {
        guard !running else { throw WorkoutError("Дождитесь текущего запроса.") }
        running = true
        defer { running = false }
        let request = try await store.prepareRecovery()
        let response = try await transport.send(request)
        guard response["recoveryId"].string != nil else { throw WorkoutError("Неверное подтверждение архива.") }
        try await store.acknowledgeRecovery(request)
    }
}
