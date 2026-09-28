import Foundation

public struct RecoveryDifference: Identifiable, Sendable {
    public let location: SetLocation
    public let exerciseName: String
    public let local: JSONValue
    public let server: JSONValue
    public var id: String { location.id }
}

/// Three-way result merge. Server owns the exercise structure; no silent resurrection of removed sets.
public enum RecoveryMerge {
    public static func differences(local: Workout, server: Workout, base: Workout?) throws -> [RecoveryDifference] {
        guard local.id == server.id, Set(local.sequence) == Set(server.sequence) else {
            throw WorkoutError("Состав подходов различается. Копии сохранены; автоматическое объединение невозможно.")
        }
        for location in server.sequence {
            let a = local.exercise(at: location), b = server.exercise(at: location)
            guard ["variantId", "equipmentId", "mode", "tracking", "unilateral"].allSatisfy({ a[$0] == b[$0] }) else {
                throw WorkoutError("Способ учёта упражнения изменился. Копии сохранены; объединение результатов требует ручной проверки.")
            }
        }
        return server.sequence.compactMap { location in
            let a = local.record(at: location), b = server.record(at: location)
            guard a != b else { return nil }
            if let base, a == base.record(at: location) || b == base.record(at: location) { return nil }
            return RecoveryDifference(location: location, exerciseName: server.exercise(at: location)["name"].string ?? "Подход", local: a, server: b)
        }
    }
    public static func merge(local: Workout, server: Workout, base: Workout?, useLocal: [String: Bool]) throws -> Workout {
        let conflicts = try differences(local: local, server: server, base: base)
        guard conflicts.allSatisfy({ useLocal[$0.id] != nil }) else { throw WorkoutError("Выберите версию каждого различающегося подхода.") }
        var payload = server.json, exercises = payload["exercises"].array
        for i in exercises.indices {
            var records = exercises[i]["records"].array
            for j in records.indices {
                let location = SetLocation(exerciseID: exercises[i]["id"].string!, setID: records[j]["id"].string!)
                let a = local.record(at: location), b = records[j]
                let takeLocal: Bool
                if a == b { takeLocal = false }
                else if let base, a == base.record(at: location) { takeLocal = false }
                else if let base, b == base.record(at: location) { takeLocal = true }
                else { takeLocal = useLocal[location.id] == true }
                if takeLocal { records[j] = a }
                if !server.active && records[j]["status"].string == "draft" {
                    throw WorkoutError("Завершённая тренировка не может содержать черновик. Выберите завершённую или пропущенную версию подхода.")
                }
            }
            exercises[i]["records"] = .array(records)
        }
        payload["exercises"] = .array(exercises)
        payload["revision"] = .int(max(local.json["revision"].integer ?? 0, server.json["revision"].integer ?? 0) + 1)
        return try Workout(json: payload)
    }
}
