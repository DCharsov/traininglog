import Foundation
import Testing
@testable import WorkoutCore

@Test func recoveryFreshnessUsesMeasurementTimeNotMidnightOrCacheRefresh() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let now = today.addingTimeInterval(12 * 3600)
    // Last completed day with data is two calendar days ago, but its evening
    // measurements are still younger than 48 hours.
    var days = (2...30).map { offset in HealthDay(date: calendar.date(byAdding: .day, value: -offset, to: today)!, sleepHours: 8, restingPulse: 60, hrvMS: 50, updatedAt: now) }
    let measured = days[0].date.addingTimeInterval(20 * 3600)
    days[0].measurementDates = ["sleepHours": measured, "restingPulse": measured, "hrvMS": measured]
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).usableMetrics == 3)
    let limit = measured.addingTimeInterval(48 * 3600)
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: limit, calendar: calendar).usableMetrics == 3)
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: limit.addingTimeInterval(1), calendar: calendar).usableMetrics == 0)
    let midnight = days[0].date
    days[0].measurementDates?["hrvMS"] = midnight
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).usableMetrics == 2)
    days[0].measurementDates?["restingPulse"] = now.addingTimeInterval(60)
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).usableMetrics == 1)
    days[0].measurementDates = nil
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).usableMetrics == 0)
}

@Test func sleepUnionDoesNotDoubleCountStages() {
    let start = Date(timeIntervalSince1970: 0)
    let intervals = [DateInterval(start: start, duration: 3600), DateInterval(start: start.addingTimeInterval(1800), duration: 3600), DateInterval(start: start.addingTimeInterval(6000), duration: 1000)]
    #expect(RecoveryAnalytics.unionSeconds(intervals) == 6400)
    #expect(RecoveryAnalytics.unionSeconds([]) == 0)
}

@Test func readinessRequiresBaselineUsesStrictQuartilesAndIgnoresToday() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_800_000_000), today = calendar.startOfDay(for: now)
    var days = (1...29).map { offset in HealthDay(date: calendar.date(byAdding: .day, value: -offset, to: today)!, sleepHours: 8, restingPulse: 60, hrvMS: 50, updatedAt: now) }
    let ordinary = RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar)
    #expect(ordinary.usableMetrics == 3 && ordinary.factors.isEmpty)
    #expect(ordinary.date == days[0].date)
    #expect(ordinary.comparisons.count == 3)
    #expect(ordinary.comparisons.allSatisfy { $0.baselineDays == 28 && !$0.unfavorable })
    #expect(ordinary.comparisons.first?.value == 8 && ordinary.comparisons.first?.threshold == 8)
    days[0].sleepHours = 5; days[0].hrvMS = 20
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).factors.count == 2)
    days.append(HealthDay(date: today, sleepHours: 20, restingPulse: 200, hrvMS: 1000, updatedAt: now))
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now, calendar: calendar).factors.count == 2)
    #expect(RecoveryAnalytics.assess(days: Array(days.prefix(10)), feeling: 1, now: now, calendar: calendar).status == "Недостаточно данных")
    #expect(RecoveryAnalytics.assess(days: Array(repeating: days[2], count: 28) + [days[0]], feeling: 5, now: now, calendar: calendar).usableMetrics == 0)
    #expect(RecoveryAnalytics.assess(days: days, feeling: nil, now: now.addingTimeInterval(3 * 86400), calendar: calendar).usableMetrics == 0)
}

@Test func recoveryDoesNotPromoteFeelingOrPartialDataToAnObjectiveAssessment() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    let now = today.addingTimeInterval(12 * 3600)
    var days = (1...15).map { offset in HealthDay(date: calendar.date(byAdding: .day, value: -offset, to: today)!, sleepHours: 8, hrvMS: 50, updatedAt: now) }
    #expect(RecoveryAnalytics.assess(days: days, feeling: 2, now: now, calendar: calendar).status == "Стоит рассмотреть более лёгкую тренировку")
    days[0].hrvMS = nil
    let partial = RecoveryAnalytics.assess(days: days, feeling: 1, now: now, calendar: calendar)
    #expect(partial.usableMetrics == 1 && partial.status == "Недостаточно данных")
    #expect(partial.factors.contains("Вы отметили низкое самочувствие"))
    days[0].hrvMS = 50
    #expect(RecoveryAnalytics.assess(days: Array(days.prefix(14)), feeling: 5, now: now, calendar: calendar).usableMetrics == 0)
    let future = HealthDay(date: today.addingTimeInterval(86400), sleepHours: 2, restingPulse: 180, hrvMS: 1, updatedAt: now)
    #expect(RecoveryAnalytics.assess(days: days + [future], feeling: 5, now: now, calendar: calendar).factors.isEmpty)
    #expect(RecoveryAnalytics.assess(days: days, feeling: 5, now: now.addingTimeInterval(3 * 86400), calendar: calendar).status == "Недостаточно данных")
}
