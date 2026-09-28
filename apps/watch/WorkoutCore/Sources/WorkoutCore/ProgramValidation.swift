import Foundation

/// Validation for user-authored Program v2, before an immutable write enters the outbox.
public enum ProgramValidation {
    public static func validate(_ program: JSONValue) throws {
        try identity(program); try text(program, "name", required: true)
        try timestamp(program, "archivedAt"); try timestamp(program, "deletedAt")
        if program.contains("contentRevision") {
            guard let revision = program["contentRevision"].integer, (1...Int64(Int32.max)).contains(revision) else { throw WorkoutError("Неверная версия содержимого программы.") }
        }
        guard let version = program["version"].integer, (1...Int64(Int32.max)).contains(version),
              case .array(let days) = program["days"], (1...30).contains(days.count) else { throw WorkoutError("Проверьте версию программы и число дней (1–30).") }
        try optionalText(program, "sourceNote"); try optionalText(program, "seedKey")
        var dayIDs = Set<String>()
        for day in days {
            try identity(day); try text(day, "name", required: true)
            try timestamp(day, "archivedAt")
            guard dayIDs.insert(day["id"].string!).inserted,
                  case .array(let exercises) = day["exercises"], (1...50).contains(exercises.count) else { throw WorkoutError("Дни должны иметь разные UUID и содержать 1–50 упражнений.") }
            var exerciseIDs = Set<String>()
            for exercise in exercises {
                try identity(exercise)
                guard exerciseIDs.insert(exercise["id"].string!).inserted else { throw WorkoutError("Повторяется UUID упражнения в дне.") }
                for key in ["variantId", "equipmentId"] {
                    guard let id = exercise[key].string, UUID(uuidString: id) != nil else { throw WorkoutError("Проверьте вариант и оборудование упражнения.") }
                }
                try text(exercise, "name", required: true); try text(exercise, "equipment", required: true)
                try text(exercise, "target"); try optionalText(exercise, "sourceNote")
                guard Workout.modes.contains(exercise["mode"].string ?? ""),
                      let sets = exercise["sets"].integer, (1...30).contains(sets),
                      exercise.contains("rest"), exercise["rest"] == .null || exercise["rest"].integer.map({ (0...1800).contains($0) }) == true else { throw WorkoutError("Проверьте способ учёта веса, подходы и отдых.") }
                if exercise.contains("tracking"), !["reps", "duration"].contains(exercise["tracking"].string ?? "") { throw WorkoutError("Неизвестный способ измерения упражнения.") }
                for key in ["optionalWeekly", "requiresEquipment", "unilateral"] {
                    if exercise.contains(key), case .bool = exercise[key] { continue }
                    if exercise.contains(key) { throw WorkoutError("Некорректный переключатель упражнения: \(key).") }
                }
                if exercise["supersetGroup"] != .null { try text(exercise, "supersetGroup", limit: 50) }
                try WeightProfile.validate(exercise)
            }
        }
    }
    private static func identity(_ value: JSONValue) throws {
        guard let id = value["id"].string, UUID(uuidString: id) != nil else { throw WorkoutError("Некорректный UUID документа или упражнения.") }
    }
    private static func text(_ value: JSONValue, _ key: String, required: Bool = false, limit: Int = 2000) throws {
        guard let text = value[key].string, text.utf16.count <= limit, !required || !text.isEmpty else { throw WorkoutError("Заполните поле \(key), не более \(limit) символов.") }
    }
    private static func optionalText(_ value: JSONValue, _ key: String) throws { if value.contains(key) { try text(value, key) } }
    private static func timestamp(_ value: JSONValue, _ key: String) throws {
        guard value[key] != .null else { return }
        let plain = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let text = value[key].string, plain.date(from: text) != nil || fractional.date(from: text) != nil else { throw WorkoutError("Неверная дата \(key).") }
    }
}
