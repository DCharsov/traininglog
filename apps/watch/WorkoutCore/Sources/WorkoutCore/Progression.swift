import Foundation

/// Port of apps/web/src/progression.ts. Suggestions are opt-in, never applied by the engine.
public enum Progression {
    public struct Entry: Sendable {
        public let session: JSONValue
        public let exercise: JSONValue
        public init(session: JSONValue, exercise: JSONValue) { self.session = session; self.exercise = exercise }
    }
    public struct Suggestion: Codable, Equatable, Sendable {
        public let weight: String
        public let reps: String
        public let duration: String
        public let note: String?
    }
    public static func repWindow(_ n: Int) -> Int { n <= 6 ? 2 : n <= 12 ? 3 : n <= 20 ? 5 : 8 }
    public static func targetRange(_ target: String, ordinal: Int) -> [Int]? {
        let parts = target.components(separatedBy: "/")
        let part = parts[min(max(ordinal, 0), parts.count - 1)]
        let numbers = part.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).compactMap(Int.init).filter { $0 > 0 && $0 <= 86400 }
        guard let first = numbers.first else { return nil }
        return numbers.count > 1 ? [numbers.min()!, numbers.max()!] : [first, first + repWindow(first)]
    }
    public static func nextWeight(_ exercise: JSONValue, grams: Int64, direction: Int64) -> Int64? {
        let step = exercise["mode"].string == "AssistedBodyweight" ? -direction : direction
        let values = Set(exercise["availableGrams"].array.compactMap(\.integer)).sorted()
        if !values.isEmpty { return step == 1 ? values.first { $0 > grams } : values.last { $0 < grams } }
        guard let size = exercise["stepGrams"].integer, size != 0 else { return nil }
        let next = grams + step * size
        return (0...2_000_000).contains(next) ? next : nil
    }
    public static func epleyReps(fromGrams: Int64, fromReps: Int, toGrams: Int64) -> Int {
        guard fromGrams > 0, toGrams > 0 else { return fromReps }
        let result = 30 * (Double(fromGrams) * (1 + Double(fromReps) / 30) / Double(toGrams) - 1)
        return max(1, Int(floor(result + 0.5)))
    }
    public static func history(sessions: [JSONValue], current: JSONValue, exercise: JSONValue, limit: Int = 3) -> [Entry] {
        let candidates = sessions.filter {
            $0["status"].string == "completed" && $0["deletedAt"] == .null && $0["id"] != current["id"] && ($0["startedAt"].string ?? "") < (current["startedAt"].string ?? "")
        }.sorted { ($0["startedAt"].string ?? "") > ($1["startedAt"].string ?? "") }
        var out: [Entry] = []
        for session in candidates {
            if let found = session["exercises"].array.first(where: { e in
                e["variantId"] == exercise["variantId"] && e["equipmentId"] == exercise["equipmentId"] && e["mode"] == exercise["mode"] && (e["tracking"].string ?? "reps") == (exercise["tracking"].string ?? "reps") && e["unilateral"].bool == exercise["unilateral"].bool && e["records"].array.contains { $0["status"].string == "completed" && $0["kind"].string == "working" }
            }) { out.append(Entry(session: session, exercise: found)) }
            if out.count >= limit { break }
        }
        return out
    }
    private static func matching(_ exercise: JSONValue, _ record: JSONValue) -> [JSONValue] {
        exercise["records"].array.filter { $0["kind"] == record["kind"] && (!exercise["unilateral"].bool || $0["side"] == record["side"]) }
    }
    private static func ordinal(_ exercise: JSONValue, _ record: JSONValue) -> Int {
        matching(exercise, record).firstIndex { $0["id"] == record["id"] } ?? -1
    }
    private static func previous(_ exercise: JSONValue, _ record: JSONValue, _ old: JSONValue) -> JSONValue? {
        let index = ordinal(exercise, record), rows = matching(old, record)
        guard rows.indices.contains(index), rows[index]["status"].string == "completed" else { return nil }
        return rows[index]
    }
    private static func done(_ exercise: JSONValue, _ record: JSONValue) -> Int? {
        record[exercise["tracking"].string == "duration" ? "durationSeconds" : "count"].integer.map(Int.init)
    }
    private static func solid(_ exercise: JSONValue) -> Bool {
        let working = exercise["records"].array.filter { $0["kind"].string == "working" }
        return !working.isEmpty && working.allSatisfy { record in
            guard record["status"].string == "completed" else { return false }
            guard let range = targetRange(exercise["target"].string ?? "", ordinal: ordinal(exercise, record)), let value = done(exercise, record) else { return true }
            return value >= range[0]
        }
    }
    public static func suggest(exercise: JSONValue, record: JSONValue, history: [Entry], today: Date = .now, calendar: Calendar = .current) -> Suggestion? {
        guard let last = history.first, let lastRecord = previous(exercise, record, last.exercise), let lastValue = done(exercise, lastRecord) else { return nil }
        let grams = lastRecord["loadGrams"].integer
        func shape(_ weight: Int64?, _ count: Int, _ note: String? = nil) -> Suggestion {
            Suggestion(weight: exercise["mode"].string == "BodyweightOnly" ? "" : weight.map { Workout.formatWeight($0).replacingOccurrences(of: ".", with: ",") } ?? "", reps: exercise["tracking"].string == "duration" ? "" : String(count), duration: exercise["tracking"].string == "duration" ? String(count) : "", note: note)
        }
        let target = exercise["target"].string ?? ""
        if record["kind"].string == "warmup" || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return shape(grams, lastValue) }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: (last.session["localDate"].string ?? "") + "T12:00:00"), today.timeIntervalSince(date) / 86400 > 21 { return shape(grams, lastValue, "После перерыва — как в прошлый раз") }
        let range = targetRange(target, ordinal: ordinal(exercise, record)), bottom = range?.first ?? 1, top = range?.last
        func before(_ index: Int) -> Int? {
            guard history.indices.contains(index), let row = previous(exercise, record, history[index].exercise), row["loadGrams"].integer == grams else { return nil }
            return done(exercise, row)
        }
        let beforeValue = before(1), thirdValue = before(2)
        if let beforeValue, lastValue <= beforeValue, top == nil || lastValue < top! {
            if let thirdValue, beforeValue <= thirdValue, let grams, let down = nextWeight(exercise, grams: grams, direction: -1) { return shape(down, top ?? lastValue, "Шаг вниз — прогресса не было") }
            return shape(grams, lastValue, "Тот же вес — в прошлый раз без прогресса")
        }
        if let top, lastValue >= top, let grams, exercise["mode"].string != "BodyweightOnly", let next = nextWeight(exercise, grams: grams, direction: 1) {
            let assisted = exercise["mode"].string == "AssistedBodyweight"
            let affordable = assisted || grams == 0 || Double(abs(next - grams)) / Double(grams) <= 0.1
            let confirmed = beforeValue.map { $0 >= top } == true && solid(last.exercise)
            if confirmed && (affordable || lastValue >= top + repWindow(top)) { return shape(next, assisted || exercise["tracking"].string == "duration" ? bottom : max(1, min(top, epleyReps(fromGrams: grams, fromReps: lastValue, toGrams: next)))) }
            if affordable { return shape(grams, lastValue) }
        }
        return shape(grams, lastValue + (exercise["tracking"].string == "duration" ? 5 : 1))
    }
}
