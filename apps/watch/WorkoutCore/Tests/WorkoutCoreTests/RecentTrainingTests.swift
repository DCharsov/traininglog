import Foundation
import Testing
@testable import WorkoutCore

private func recentSession(_ date: String) -> JSONValue {
    .object(["programId": .string("PROGRAM"), "dayId": .string("LEGS"), "localDate": .string(date),
             "status": .string("completed"), "exercises": .array([.object(["records": .array([.object(["status": .string("completed")])])])])])
}
private let recentNow = ISO8601DateFormatter().date(from: "2026-09-29T20:00:00Z")!
private var recentCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
    return calendar
}
private func recent(_ sessions: [JSONValue]) -> String? {
    RecentTraining.lastDate(sessions: sessions, programID: "program", dayID: "legs", now: recentNow, calendar: recentCalendar)
}
@Test func recentTrainingUsesSevenLocalDaysAndLatestCompletion() {
    #expect(recent([recentSession("2026-09-24")]) == "2026-09-24")
    #expect(recent([recentSession("2026-09-23")]) == nil)
    #expect(recent([recentSession("2026-09-30")]) == "2026-09-30")
    #expect(recent([recentSession("2026-10-01")]) == nil)
    #expect(recent([recentSession("2026-09-24"), recentSession("2026-09-29"), recentSession("2026-09-27")]) == "2026-09-29")
}
@Test func recentTrainingExcludesUnfinishedDeletedOtherDaysAndEmptyTests() {
    for (key, value) in [("status", "active"), ("status", "cancelled"), ("deletedAt", "2026-09-29"), ("programId", "other"), ("dayId", "shoulders"), ("localDate", "2026-09-xx")] {
        var session = recentSession("2026-09-29"); session[key] = .string(value)
        #expect(recent([session]) == nil)
    }
    var session = recentSession("2026-09-29")
    session["exercises"] = .array([.object(["records": .array([.object(["status": .string("skipped")])])])])
    #expect(recent([session]) == nil)
}
