import Foundation

/// Diary-only statistics; no HealthKit quantities enter these models.
public enum TrainingProgress {
    public struct Context: Hashable, Sendable, Identifiable {
        public let variant: String
        public let equipment: String
        public let mode: String
        public let tracking: String
        public let unilateral: Bool
        public var id: String { [variant, equipment, mode, tracking, String(unilateral)].joined(separator: "|") }
        public init(_ e: JSONValue) {
            variant = e["variantId"].string ?? ""; equipment = e["equipmentId"].string ?? ""
            mode = e["mode"].string ?? ""; tracking = e["tracking"].string ?? "reps"; unilateral = e["unilateral"].bool
        }
    }
    public struct Row: Sendable {
        public let session: JSONValue
        public let exercise: JSONValue
        public let record: JSONValue
    }
    public struct Point: Identifiable, Sendable {
        public let id: String
        public let date: String
        public let value: Double
    }
    public static func results(_ sessions: [JSONValue], context: Context? = nil, side: String? = nil, from: String? = nil, to: String? = nil) -> [Row] {
        sessions.filter {
            $0["status"].string == "completed" && $0["deletedAt"] == .null && (from == nil || ($0["localDate"].string ?? "") >= from!) && (to == nil || ($0["localDate"].string ?? "") <= to!)
        }.sorted {
            let a = $0["startedAt"].string ?? "", b = $1["startedAt"].string ?? ""
            return a == b ? ($0["id"].string ?? "") < ($1["id"].string ?? "") : a < b
        }.flatMap { session in
            session["exercises"].array.filter { context == nil || Context($0) == context }.flatMap { exercise in
                exercise["records"].array.compactMap { record -> Row? in
                    guard record["status"].string == "completed", record["kind"].string == "working",
                          record[exercise["tracking"].string == "duration" ? "durationSeconds" : "count"].integer != nil,
                          side == nil || (record["side"].string ?? "both") == side,
                          exercise["mode"].string == "BodyweightOnly" || record["loadGrams"].integer != nil else { return nil }
                    return Row(session: session, exercise: exercise, record: record)
                }
            }
        }
    }
    /// Matches progress.ts points: one best value per session; less assistance is better.
    public static func points(_ rows: [Row], metric: String, minReps: Int64 = 1, weight: Int64? = nil) -> [Point] {
        var values: [String: Point] = [:], order: [String] = []
        for row in rows {
            let r = row.record, e = row.exercise
            if metric != "duration" && (r["count"].integer ?? 0) < minReps { continue }
            if ["reps", "duration"].contains(metric), e["mode"].string != "BodyweightOnly", r["loadGrams"].integer != weight { continue }
            guard let value = r[metric == "duration" ? "durationSeconds" : metric == "load" ? "loadGrams" : "count"].integer else { continue }
            let id = row.session["id"].string ?? "", lower = metric == "load" && e["mode"].string == "AssistedBodyweight"
            if values[id] == nil { order.append(id) }
            if let old = values[id], lower ? Double(value) >= old.value : Double(value) <= old.value { continue }
            values[id] = Point(id: id, date: row.session["localDate"].string ?? "", value: Double(value))
        }
        return order.compactMap { values[$0] }
    }
    /// Only comparable external load × repetitions. No invented body mass, assistance or duration tonnage.
    public static func volume(_ rows: [Row]) -> Double? {
        guard let first = rows.first else { return nil }
        let context = Context(first.exercise)
        guard context.tracking == "reps", !["BodyweightOnly", "AssistedBodyweight", "Unspecified"].contains(context.mode), rows.allSatisfy({ Context($0.exercise) == context }) else { return nil }
        return rows.reduce(0) { $0 + Double($1.record["loadGrams"].integer ?? 0) / 1000 * Double($1.record["count"].integer ?? 0) }
    }
    public static func elapsedMinutes(_ session: JSONValue) -> Double? {
        func parse(_ value: JSONValue) -> Date? {
            guard let text = value.string else { return nil }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: text) { return date }
            f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
        }
        guard session["status"].string == "completed", let start = parse(session["startedAt"]), let end = parse(session["completedAt"]), end >= start else { return nil }
        return end.timeIntervalSince(start) / 60
    }
}
