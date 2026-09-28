import Foundation

public struct SetLocation: Codable, Hashable, Sendable, Identifiable {
    public let exerciseID: String
    public let setID: String
    public var id: String { setID }
    public init(exerciseID: String, setID: String) { self.exerciseID = exerciseID; self.setID = setID }
}

public struct Workout: Codable, Equatable, Sendable {
    public private(set) var json: JSONValue
    public var exercises: [JSONValue] { json["exercises"].array }
    public var id: String { json["id"].string ?? "" }
    public var active: Bool { json["status"].string == "active" }
    public var restEndsAt: Int64? { json["restEndsAt"].integer }

    public init(json: JSONValue) throws {
        self.json = json
        try validateCompatibility()
    }

    public func validateCompatibility() throws {
        guard UUID(uuidString: id) != nil,
              ["active", "completed", "cancelled"].contains(json["status"].string ?? ""),
              (json["revision"].integer ?? 0) > 0,
              case .array = json["exercises"], exercises.count <= 50 else {
            throw WorkoutError("Неподдерживаемый формат тренировки. Данные не изменены.")
        }
        var exerciseIDs = Set<String>(), setIDs = Set<String>()
        for e in exercises {
            guard let eid = e["id"].string, UUID(uuidString: eid) != nil, exerciseIDs.insert(eid).inserted,
                  Self.modes.contains(e["mode"].string ?? ""),
                  !e.contains("tracking") || ["reps", "duration"].contains(e["tracking"].string ?? ""),
                  case .array = e["records"], e["records"].array.count <= 100 else {
                throw WorkoutError("Обновите приложение: неизвестный формат упражнения.")
            }
            for r in e["records"].array {
                guard let sid = r["id"].string, UUID(uuidString: sid) != nil, setIDs.insert(sid).inserted,
                      ["draft", "completed", "skipped"].contains(r["status"].string ?? ""),
                      ["working", "warmup"].contains(r["kind"].string ?? ""),
                      !r.contains("side") || ["both", "left", "right"].contains(r["side"].string ?? "") else {
                    throw WorkoutError("Обновите приложение: неизвестный формат подхода.")
                }
            }
        }
    }

    public static let modes = ["Unspecified", "BarbellTotal", "SmithPlatesOnly", "PerDumbbell", "MachinePlatesOnly", "MachineStack", "AddedBodyweight", "AssistedBodyweight", "BodyweightOnly"]

    public func exercise(at location: SetLocation) -> JSONValue {
        exercises.first { $0["id"].string == location.exerciseID } ?? .null
    }
    public func record(at location: SetLocation) -> JSONValue {
        exercise(at: location)["records"].array.first { $0["id"].string == location.setID } ?? .null
    }

    public var sequence: [SetLocation] {
        let labels = exercises.map { Self.label($0["sourceNote"].string ?? "") }
        let groups: [String?] = exercises.enumerated().map { i, e in
            if e.contains("supersetGroup") { return e["supersetGroup"].string }
            guard let own = labels[i], labels.filter({ $0?.0 == own.0 }).count == 1,
                  labels.filter({ $0?.0 == own.1 && $0?.1 == own.0 }).count == 1 else { return nil }
            return String(own.0.prefix(1))
        }
        var used = Set<Int>(), result: [SetLocation] = []
        for i in exercises.indices where !used.contains(i) {
            let indices = groups[i].map { group in
                group.isEmpty ? [i] : exercises.indices.filter { groups[$0] == group && !used.contains($0) }
            } ?? [i]
            used.formUnion(indices)
            for r in 0..<(indices.map { exercises[$0]["records"].array.count }.max() ?? 0) {
                for n in indices where r < exercises[n]["records"].array.count {
                    result.append(SetLocation(exerciseID: exercises[n]["id"].string!, setID: exercises[n]["records"].array[r]["id"].string!))
                }
            }
        }
        return result
    }
    public var next: SetLocation? { sequence.first { record(at: $0)["status"].string == "draft" } }

    private static func label(_ text: String) -> (String, String)? {
        let regex = try! NSRegularExpression(pattern: "^([A-Z][12])\\s*·\\s*Суперсет с ([A-Z][12])(?:\\s*·|$)")
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text) else { return nil }
        return (String(text[a]), String(text[b]))
    }

    private mutating func edit(_ location: SetLocation, _ update: (inout JSONValue, JSONValue) throws -> Void) throws {
        guard active else { throw WorkoutError("Тренировка уже завершена.") }
        var all = exercises
        guard let e = all.firstIndex(where: { $0["id"].string == location.exerciseID }) else { throw WorkoutError("Упражнение не найдено.") }
        var records = all[e]["records"].array
        guard let r = records.firstIndex(where: { $0["id"].string == location.setID }) else { throw WorkoutError("Подход не найден.") }
        try update(&records[r], all[e])
        all[e]["records"] = .array(records)
        json["exercises"] = .array(all)
    }

    /// Only an entirely untouched draft is eligible. No copying RIR, notes or completion metadata.
    @discardableResult public mutating func autofill(_ location: SetLocation) throws -> Bool {
        let records = exercise(at: location)["records"].array
        guard let index = records.firstIndex(where: { $0["id"].string == location.setID }) else { throw WorkoutError("Подход не найден.") }
        let current = records[index]
        guard current["status"].string == "draft", current["completedAt"] == .null,
              ["weight", "reps", "duration", "rir", "note"].allSatisfy({ (current[$0].string ?? "").isEmpty }),
              ["loadGrams", "count", "durationSeconds"].allSatisfy({ current[$0] == .null }),
              let previous = records[..<index].last(where: {
                  $0["status"].string == "completed" && $0["kind"] == current["kind"] &&
                  ($0["side"].string ?? "both") == (current["side"].string ?? "both")
              }) else { return false }
        try edit(location) { r, e in
            if e["mode"].string != "BodyweightOnly" { r["weight"] = previous["weight"] }
            let field = e["tracking"].string == "duration" ? "duration" : "reps"
            r[field] = previous[field]
        }
        return true
    }

    public mutating func setField(_ location: SetLocation, field: String, value: String) throws {
        guard ["weight", "reps", "duration", "rir", "note"].contains(field), value.count <= 2000 else { throw WorkoutError("Недопустимое поле.") }
        try edit(location) { r, _ in
            guard r["status"].string == "draft" else { throw WorkoutError("Сначала откройте исправление подхода.") }
            r[field] = .string(value)
        }
    }

    @discardableResult public mutating func complete(_ location: SetLocation, now: Date) throws -> Bool {
        if record(at: location)["status"].string == "completed" { return false }
        let first = record(at: location)["completedAt"] == .null
        try edit(location) { r, e in
            guard r["status"].string == "draft" else { throw WorkoutError("Подход пропущен.") }
            if e["requiresEquipment"].bool && e["mode"].string == "Unspecified" { throw WorkoutError("Выберите оборудование на телефоне перед передачей.") }
            let duration = e["tracking"].string == "duration"
            let count = try Self.whole(r[duration ? "duration" : "reps"].string ?? "", digits: duration ? 5 : 4, minimum: 1, maximum: duration ? 86400 : 1000)
            if let rir = r["rir"].string, !rir.isEmpty { _ = try Self.whole(rir, digits: 2, minimum: 0, maximum: 10) }
            r["loadGrams"] = e["mode"].string == "BodyweightOnly" ? .null : .int(try Self.parseWeight(r["weight"].string ?? ""))
            if e["unilateral"].bool && !["left", "right"].contains(r["side"].string ?? "") { throw WorkoutError("Не выбрана сторона упражнения.") }
            r["count"] = duration ? .null : .int(count)
            r["durationSeconds"] = duration ? .int(count) : .null
            if !e["unilateral"].bool { r["side"] = .string("both") }
            r["status"] = .string("completed")
            r["completedAt"] = .string(Self.timestamp(now))
        }
        if first {
            let rest = RestRules.seconds(exercise(at: location))
            json["restEndsAt"] = rest > 0 ? .int(Self.milliseconds(now) + rest * 1000) : .null
        }
        return true
    }

    /// Edit an already completed historical set without reopening the workout or changing its timing.
    public mutating func correctHistory(_ location: SetLocation, values: [String: String]) throws {
        guard json["status"].string == "completed", json["deletedAt"] == .null,
              sequence.contains(location), record(at: location)["status"].string == "completed" else {
            throw WorkoutError("Можно исправить только выполненный подход завершённой тренировки.")
        }
        let original = json, completedAt = record(at: location)["completedAt"]
        var edited = self
        edited.json["status"] = .string("active")
        try edited.correct(location)
        for field in ["weight", "reps", "duration", "rir", "note"] {
            if let value = values[field] { try edited.setField(location, field: field, value: value) }
        }
        _ = try edited.complete(location, now: Date())
        try edited.edit(location) { record, _ in record["completedAt"] = completedAt }
        edited.json["status"] = original["status"]
        edited.json["completedAt"] = original["completedAt"]
        edited.json["restEndsAt"] = original["restEndsAt"]
        self = edited
    }

    public mutating func correct(_ location: SetLocation) throws {
        try edit(location) { r, _ in
            guard r["status"].string == "completed" else { throw WorkoutError("Нет выполненного подхода для исправления.") }
            r["status"] = .string("draft") // completedAt remains: corrections must not restart rest.
        }
    }
    public mutating func skip(_ location: SetLocation) throws {
        try edit(location) { r, _ in
            guard r["status"].string == "draft" else { throw WorkoutError("Подход уже записан.") }
            r["status"] = .string("skipped")
        }
        json["restEndsAt"] = .null
    }
    public mutating func changeRest(seconds: Int64?, now: Date) throws {
        guard active else { throw WorkoutError("Тренировка завершена.") }
        guard let seconds else { json["restEndsAt"] = .null; return }
        let end = max(Self.milliseconds(now), restEndsAt ?? Self.milliseconds(now)) + seconds * 1000
        json["restEndsAt"] = end > Self.milliseconds(now) ? .int(end) : .null
    }
    public mutating func finish(now: Date) throws {
        guard active else { throw WorkoutError("Тренировка завершена.") }
        var all = exercises
        for i in all.indices {
            var records = all[i]["records"].array
            for j in records.indices where records[j]["status"].string != "completed" { records[j]["status"] = .string("skipped") }
            all[i]["records"] = .array(records)
        }
        json["exercises"] = .array(all)
        json["status"] = .string("completed")
        json["completedAt"] = .string(Self.timestamp(now))
        json["restEndsAt"] = .null
    }
    public mutating func incrementRevision() { json["revision"] = .int((json["revision"].integer ?? 0) + 1) }
    public static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded(.down)) }
    public static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: date)
    }
    private static func whole(_ input: String, digits: Int, minimum: Int64, maximum: Int64) throws -> Int64 {
        guard input.matches("^[0-9]{1,\(digits)}$"), let n = Int64(input), (minimum...maximum).contains(n) else {
            throw WorkoutError("Введите целое число от \(minimum) до \(maximum).")
        }
        return n
    }
    public static func parseWeight(_ input: String) throws -> Int64 {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.matches("^[0-9]{1,4}(?:[.,][0-9]{1,3})?$") else { throw WorkoutError("Введите вес, например 72,5 (до трёх знаков после запятой).") }
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: ".")
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let grams = Int64(parts[0])! * 1000 + Int64(fraction.padding(toLength: 3, withPad: "0", startingAt: 0))!
        guard grams <= 2_000_000 else { throw WorkoutError("Вес должен быть от 0 до 2000 кг.") }
        return grams
    }
    public static func formatWeight(_ grams: Int64) -> String {
        let fraction = String(format: "%03lld", grams % 1000).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return "\(grams / 1000)" + (fraction.isEmpty ? "" : "," + fraction)
    }
    public static func adjustedWeight(_ e: JSONValue, input: String, direction: Int64, manualStepGrams: Int64? = nil) throws -> String {
        try WeightProfile.validate(e)
        guard direction == 1 || direction == -1 else { throw WorkoutError("Неизвестное направление изменения веса.") }
        let current = try parseWeight(input), values = Set(e["availableGrams"].array.compactMap(\.integer)).sorted()
        let next: Int64?
        if !values.isEmpty { next = direction > 0 ? values.first { $0 > current } : values.last { $0 < current } }
        else if let step = e["stepGrams"].integer, step > 0 { next = current + direction * step }
        else if let step = manualStepGrams, (1...2_000_000).contains(step) { next = max(0, min(2_000_000, current + (direction > 0 ? step : -step))) }
        else { next = nil }
        guard let next, (0...2_000_000).contains(next) else { throw WorkoutError("Нет доступного веса. Введите вручную.") }
        return formatWeight(next)
    }
}
