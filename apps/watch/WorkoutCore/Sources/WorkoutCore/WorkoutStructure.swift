import Foundation

public enum WorkoutStructureChange: Sendable {
    case warmup(exerciseID: String)
    case add(JSONValue)
    case reorder([String])
}
extension Workout {
    public func changingStructure(_ change: WorkoutStructureChange) throws -> Workout {
        guard active else { throw WorkoutError("Структуру завершённой тренировки менять нельзя.") }
        var payload = json, all = exercises
        switch change {
        case .warmup(let exerciseID):
            guard let i = all.firstIndex(where: { $0["id"].string == exerciseID }) else { throw WorkoutError("Упражнение не найдено.") }
            var records = all[i]["records"].array
            let sides = all[i]["unilateral"].bool ? ["left", "right"] : ["both"]
            let insert = records.firstIndex { $0["kind"].string == "working" } ?? records.count
            let added = sides.map { side -> JSONValue in
                .object(["id": .string(UUID().uuidString), "status": .string("draft"), "kind": .string("warmup"), "side": .string(side), "weight": .string(""), "reps": .string(""), "duration": .string(""), "rir": .string(""), "note": .string(""), "loadGrams": .null, "count": .null, "durationSeconds": .null, "completedAt": .null])
            }
            records.insert(contentsOf: added, at: insert); all[i]["records"] = .array(records)
        case .add(var exercise):
            exercise["id"] = .string(UUID().uuidString); exercise["optionalWeekly"] = .bool(false)
            let day: JSONValue = .object(["id": json["dayId"], "name": json["name"], "exercises": .array([exercise])])
            let program: JSONValue = .object(["id": json["programId"], "version": json["programVersion"]])
            all.append(contentsOf: try PhoneDiary.makeWorkout(program: program, day: day).exercises)
        case .reorder(let ids):
            let original = all.compactMap { $0["id"].string }
            guard ids.count == original.count, Set(ids) == Set(original), Set(ids).count == ids.count else { throw WorkoutError("Список упражнений изменился. Обновите экран.") }
            all = ids.map { id in all.first { $0["id"].string == id }! }
        }
        payload["exercises"] = .array(all)
        var next = try Workout(json: payload); next.incrementRevision(); return next
    }
}
