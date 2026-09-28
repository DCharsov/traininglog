import Foundation
import Testing
@testable import WorkoutCore

@Test func sharedProgressionMatchesWebsite() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WorkoutCore/Resources/progression-cases.json")
    let cases = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)).array
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
    for c in cases {
        let record: JSONValue = .object(["id": .string("set"), "kind": c["kind"].string.map(JSONValue.string) ?? .string("working"), "status": .string("draft"), "side": .string("left")])
        var right = record; right["id"] = .string("right"); right["side"] = .string("right"); right["status"] = .string("completed"); right["loadGrams"] = .int(90000); right["count"] = .int(99)
        var exercise = c; exercise["records"] = .array(c["unilateral"].bool ? [right, record] : [record])
        let history = c["values"].array.enumerated().map { index, value -> Progression.Entry in
            var old = exercise, row = record
            row["status"] = .string(c["missing"].bool ? "skipped" : "completed"); row["loadGrams"] = c["grams"]; row["count"] = value; row["durationSeconds"] = value
            var rows = c["unilateral"].bool ? [right, row] : [row]
            if c["skip"].bool && index == 0 { var skipped = record; skipped["id"] = .string("skip"); skipped["status"] = .string("skipped"); rows.append(skipped) }
            old["records"] = .array(rows)
            let date = c["old"].bool ? "2026-07-01" : String(format: "2026-09-%02d", 10 - index * 3)
            return Progression.Entry(session: .object(["localDate": .string(date)]), exercise: old)
        }
        let result = Progression.suggest(exercise: exercise, record: record, history: history, today: today, calendar: calendar)
        let expected = try JSONDecoder().decode(Progression.Suggestion?.self, from: JSONEncoder().encode(c["expected"]))
        #expect(result == expected, "\(c["name"].string ?? "")")
    }
}
