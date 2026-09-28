import Foundation

extension WorkoutStore {
    /// Called only on an explicit start, after both devices durably acknowledged preparation.
    public func startReserved(_ reservation: JSONValue, deviceID: String, now: Date = .now, calendar: Calendar = .current) throws -> WorkoutState {
        _ = try load()
        guard reservation["state"].string == "ready", reservation["phoneReady"].bool, reservation["watchReady"].bool,
              reservation["protocolVersion"].integer == 1, reservation["contractVersion"].integer == 2,
              reservation["deviceId"].string == deviceID, let generation = reservation["generation"].string,
              let version = reservation["version"].integer, version > 0,
              let epoch = reservation["controlEpoch"].integer, epoch > 0 else { throw WorkoutError("Тренировка ещё не готова для запуска без интернета.") }
        var payload = reservation["payload"]
        guard payload["id"] == reservation["reservationId"] else { throw WorkoutError("UUID резерва не совпадает.") }
        if let existing = state {
            if existing.workout.id == payload["id"].string { return existing } // Double tap / interrupted transition.
            guard existing.isDemo || existing.sync?.recovered == true || (existing.sync?.controlState == "phone" && existing.sync?.pending == nil && existing.sync?.conflict == nil) else { throw WorkoutError("Сначала отправьте или восстановите предыдущую тренировку.") }
            let archive = file.deletingLastPathComponent().appendingPathComponent("archive", isDirectory: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try JSONEncoder().encode(existing).write(to: archive.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        }
        let prepared = try Workout(json: payload)
        guard prepared.active, prepared.sequence.allSatisfy({ prepared.record(at: $0)["status"].string == "draft" && prepared.record(at: $0)["completedAt"] == .null }) else { throw WorkoutError("Резерв содержит уже выполненные подходы.") }
        payload["startedAt"] = .string(Workout.timestamp(now)); payload["completedAt"] = .null; payload["restEndsAt"] = .null
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        payload["localDate"] = .string(f.string(from: now)); payload["timezone"] = .string(calendar.timeZone.identifier)
        var workout = try Workout(json: payload); workout.incrementRevision()
        var next = WorkoutState(workout: workout, isDemo: false)
        next.localRevision = 1
        let request = WatchRequest(path: "/watch/v1/reservation/start", method: "POST", body: .object([
            "operationId": .string(UUID().uuidString), "generation": .string(generation), "reservationId": .string(workout.id),
            "version": .int(version), "controlEpoch": .int(epoch), "payload": workout.json
        ]), revision: next.localRevision)
        next.sync = SyncContext(generation: generation, baseVersion: 0, controlEpoch: epoch, controlState: "watch", deviceID: deviceID, basePayload: workout.json, pending: request)
        try persist(next) // Editor and HealthKit can start only after this atomic write succeeds.
        return next
    }
}
