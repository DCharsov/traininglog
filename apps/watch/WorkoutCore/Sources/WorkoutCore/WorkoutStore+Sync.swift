import Foundation

extension WorkoutStore {
    public func receiveOffer(_ snapshot: JSONValue, deviceID: String) throws -> WorkoutState {
        _ = try load()
        guard snapshot["protocolVersion"].integer == 1, snapshot["contractVersion"].integer == 2,
              snapshot["control"]["deviceId"].string == deviceID,
              let generation = snapshot["generation"].string,
              let version = snapshot["version"].integer, let epoch = snapshot["control"]["controlEpoch"].integer else {
            throw WorkoutError("Некорректное предложение тренировки.")
        }
        let workout = try Workout(json: snapshot["payload"])
        guard workout.id == snapshot["sessionId"].string else { throw WorkoutError("ID тренировки не совпадает.") }
        if let existing = state, existing.workout.id == workout.id, !existing.isDemo,
           existing.sync?.controlState != "phone", existing.sync?.recovered != true {
            // Never replace offline edits with a fetched copy, even if its version is newer.
            return existing
        }
        if let existing = state {
            guard existing.isDemo || existing.sync?.recovered == true || (existing.sync?.controlState == "phone" && existing.sync?.pending == nil && existing.sync?.conflict == nil) else {
                throw WorkoutError("Сначала отправьте или восстановите сохранённую тренировку.")
            }
            let archive = file.deletingLastPathComponent().appendingPathComponent("archive", isDirectory: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try JSONEncoder().encode(existing).write(to: archive.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        }
        guard snapshot["control"]["state"].string == "offered", let handoffID = snapshot["control"]["handoffId"].string else {
            throw WorkoutError("Часы уже владеют тренировкой, но локальная копия отсутствует. Верните управление на телефоне и передайте заново.")
        }
        var next = WorkoutState(workout: workout, isDemo: false)
        let body: JSONValue = .object([
            "operationId": .string(UUID().uuidString), "sessionId": .string(workout.id), "generation": .string(generation),
            "baseVersion": .int(version), "controlEpoch": .int(epoch), "handoffId": .string(handoffID)
        ])
        next.sync = SyncContext(generation: generation, baseVersion: version, controlEpoch: epoch, controlState: "offered", deviceID: deviceID, basePayload: workout.json,
            pending: WatchRequest(path: "/watch/v1/handoff/accept", method: "POST", body: body))
        try persist(next) // Durable before accepting; editor stays disabled until acknowledgement.
        return next
    }

    public func requestReturn() throws -> WorkoutState {
        _ = try load()
        guard var next = state, next.sync?.controlState == "watch", next.sync?.conflict == nil else { throw WorkoutError("Нет тренировки под управлением часов.") }
        next.sync?.returning = true
        try persist(next)
        return next
    }

    public func prepareRequest(deviceID: String) throws -> WatchRequest? {
        _ = try load()
        guard var next = state, !next.isDemo, var sync = next.sync else { return nil }
        if sync.recovery != nil { return nil }
        guard sync.deviceID == deviceID else { throw WorkoutError("Это новое подключение. Сначала сохраните восстановительную копию и подтвердите возврат на телефоне.") }
        guard sync.conflict == nil else { throw WorkoutError("Есть конфликт управления. Сохраните восстановительную копию.") }
        if let pending = sync.pending { return pending }
        guard sync.controlState == "watch" else { return nil }
        var body: JSONValue = .object([
            "operationId": .string(UUID().uuidString), "sessionId": .string(next.workout.id), "generation": .string(sync.generation),
            "baseVersion": .int(sync.baseVersion), "controlEpoch": .int(sync.controlEpoch)
        ])
        let request: WatchRequest
        if next.workout.json != sync.basePayload {
            body["protocolVersion"] = .int(1); body["contractVersion"] = .int(2); body["payload"] = next.workout.json
            request = WatchRequest(path: "/watch/v1/sessions/\(next.workout.id)", method: "PUT", body: body, revision: next.localRevision)
        } else if sync.returning {
            request = WatchRequest(path: "/watch/v1/control/release", method: "POST", body: body, revision: next.localRevision)
        } else { return nil }
        sync.pending = request; next.sync = sync
        try persist(next)
        return request
    }

    public func acknowledge(_ request: WatchRequest, response: JSONValue) throws {
        guard var next = state, var sync = next.sync, sync.pending == request else { throw WorkoutError("Подтверждение не соответствует сохранённому запросу.") }
        guard response["generation"].string == sync.generation,
              let version = response["version"].integer, version > sync.baseVersion,
              let epoch = response["control"]["controlEpoch"].integer,
              let control = response["control"]["state"].string, ["watch", "phone"].contains(control) else { throw WorkoutError("Неверное подтверждение сервера. Запрос сохранён для повтора.") }
        sync.baseVersion = version; sync.controlEpoch = epoch; sync.controlState = control
        if request.method == "PUT" { sync.basePayload = request.body["payload"] }
        if request.path == "/watch/v1/handoff/accept", let selected = next.selected {
            if try next.workout.autofill(selected) { next.workout.incrementRevision(); next.localRevision += 1 }
        }
        sync.pending = nil; sync.lastSyncedAt = Workout.milliseconds(Date())
        if control == "phone" { sync.returning = false }
        next.sync = sync
        try persist(next)
    }
    public func markConflict(_ response: JSONValue) throws {
        guard var next = state, next.sync != nil else { return }
        next.sync?.conflict = response
        try persist(next)
    }
    public func prepareRecovery() throws -> WatchRequest {
        guard var next = state, !next.isDemo, next.sync != nil else { throw WorkoutError("Нет серверной тренировки для восстановления.") }
        if let request = next.sync?.recovery { return request }
        let request = WatchRequest(path: "/watch/v1/recovery", method: "POST", body: .object([
            "operationId": .string(UUID().uuidString), "sessionId": .string(next.workout.id), "payload": next.workout.json
        ]), revision: next.localRevision)
        next.sync?.recovery = request
        next.sync?.returning = true // Freeze the archived snapshot until owner-mediated recovery.
        try persist(next)
        return request
    }
    public func acknowledgeRecovery(_ request: WatchRequest) throws {
        guard var next = state, next.sync?.recovery == request else { throw WorkoutError("Неизвестная восстановительная копия.") }
        next.sync?.recovered = true
        try persist(next)
    }
}
