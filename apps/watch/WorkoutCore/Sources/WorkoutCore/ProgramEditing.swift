import Foundation

/// Copies retain exercise/equipment comparison identities but never reuse editable row IDs.
public enum ProgramEditing {
    public static func setDayArchived(_ day: JSONValue, archived: Bool, now: Date = .now) -> JSONValue {
        var result = day; result["archivedAt"] = archived ? .string(Workout.timestamp(now)) : .null
        return result
    }
    public static func copyDay(_ original: JSONValue) -> JSONValue {
        var day = original
        day["id"] = .string(UUID().uuidString)
        day["archivedAt"] = .null
        day["name"] = .string((original["name"].string ?? "День") + " · копия")
        day["exercises"] = .array(original["exercises"].array.map { value in
            var exercise = value
            exercise["id"] = .string(UUID().uuidString)
            return exercise
        })
        return day
    }

    public static func copyProgram(_ original: JSONValue) -> JSONValue {
        var result = original
        result["id"] = .string(UUID().uuidString)
        result["version"] = .int(1)
        if case .object(var fields) = result {
            fields.removeValue(forKey: "seedKey")
            result = .object(fields)
        }
        result["name"] = .string((original["name"].string ?? "Программа") + " · копия")
        result["archivedAt"] = .null
        result["deletedAt"] = .null
        result["days"] = .array(original["days"].array.map { originalDay in
            var day = copyDay(originalDay)
            day["name"] = originalDay["name"]
            return day
        })
        return result
    }
}
