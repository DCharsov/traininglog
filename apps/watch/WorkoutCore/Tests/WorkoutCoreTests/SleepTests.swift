import Foundation
import Testing
@testable import WorkoutCore

private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
@Test func wakeRegularityUsesCircularClockAndRequiresThreeValidDays() {
    let midnight = SleepAnalytics.wakeWindow([1420, 1430, 10, 20])!
    #expect(midnight.startMinutes == 1427.5 && midnight.endMinutes == 12.5)
    #expect(midnight.spreadMinutes == 25)
    let morning = SleepAnalytics.wakeWindow([420, 440, 460, 480])!
    #expect(morning.startMinutes == 435 && morning.endMinutes == 465 && morning.spreadMinutes == 30)
    #expect(SleepAnalytics.wakeWindow([480, 480, 480])?.spreadMinutes == 0)
    #expect(SleepAnalytics.wakeWindow([10, 20, .nan, .infinity, -1, 1440]) == nil)
}
@Test func sleepUsesWakeDateAndUnionsStagesAndDuplicates() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = instant("2026-09-27T22:00:00Z"), end = instant("2026-09-28T06:00:00Z")
    let deep = SleepInterval(start: start, end: start.addingTimeInterval(7200), stage: .deep)
    let samples = [SleepInterval(start: start, end: end, stage: .unspecified), deep, deep,
                   SleepInterval(start: start.addingTimeInterval(7200), end: end, stage: .core),
                   SleepInterval(start: start.addingTimeInterval(-3600), end: end.addingTimeInterval(3600), stage: .inBed)]
    let rows = SleepAnalytics.days(samples, calendar: calendar)
    #expect(rows.count == 1)
    #expect(rows[0].date == instant("2026-09-28T00:00:00Z"))
    #expect(rows[0].sleepHours == 8 && rows[0].deepHours == 2 && rows[0].coreHours == 6)
    #expect(rows[0].wakeMinutes == 360)
    #expect(SleepAnalytics.days([], calendar: calendar).isEmpty) // Deletion rebuilds, never accumulates cache.
}
@Test func sleepAcrossDSTAndTimezoneUsesElapsedSecondsAndLocalWakeDate() {
    var berlin = Calendar(identifier: .gregorian); berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let samples = [SleepInterval(start: instant("2026-03-28T22:00:00Z"), end: instant("2026-03-29T06:00:00Z"), stage: .unspecified)]
    let row = SleepAnalytics.days(samples, calendar: berlin)[0]
    #expect(row.sleepHours == 8) // Wall clock jumped; elapsed sleep did not.
    #expect(row.wakeMinutes == 480)
    var pacific = Calendar(identifier: .gregorian); pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let western = SleepAnalytics.days(samples, calendar: pacific)[0]
    #expect(pacific.component(.day, from: western.date) == 28)
    #expect(western.sleepHours == 8)
}
@Test func napsDoNotReplaceMainWakeTimeAndContradictoryStagesAreNotDoubled() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = instant("2026-09-28T00:00:00Z")
    let samples = [SleepInterval(start: start, end: start.addingTimeInterval(8*3600), stage: .core),
                   SleepInterval(start: start, end: start.addingTimeInterval(2*3600), stage: .deep),
                   SleepInterval(start: start.addingTimeInterval(14*3600), end: start.addingTimeInterval(15*3600), stage: .rem)]
    let row = SleepAnalytics.days(samples, calendar: calendar)[0]
    #expect(row.sleepHours == 9)
    #expect(row.coreHours == 6 && row.deepHours == nil && row.remHours == 1)
    #expect(row.wakeMinutes == 480)
}
