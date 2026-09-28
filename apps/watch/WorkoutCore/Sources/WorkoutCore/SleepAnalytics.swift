import Foundation

public struct SleepInterval: Sendable {
    public enum Stage: String, Sendable { case unspecified, core, deep, rem, awake, inBed }
    public let interval: DateInterval
    public let stage: Stage
    public init(start: Date, end: Date, stage: Stage) { interval = DateInterval(start: start, end: max(start, end)); self.stage = stage }
}
public enum SleepAnalytics {
    public struct WakeWindow: Equatable, Sendable {
        public let startMinutes: Double
        public let endMinutes: Double
        public let spreadMinutes: Double
    }
    /// Clock time is circular: 23:50 and 00:10 are twenty minutes apart, not almost a day.
    /// Unwrap at the largest empty gap, then report the middle half of observed wake times.
    public static func wakeWindow(_ minutes: [Double]) -> WakeWindow? {
        let values = minutes.filter { $0.isFinite && $0 >= 0 && $0 < 1440 }.sorted()
        guard values.count >= 3 else { return nil }
        var largestGap = -1.0, origin = values[0]
        for index in values.indices {
            let next = index + 1 < values.count ? values[index + 1] : values[0] + 1440
            if next - values[index] > largestGap { largestGap = next - values[index]; origin = next.truncatingRemainder(dividingBy: 1440) }
        }
        let unwrapped = values.map { $0 < origin ? $0 + 1440 : $0 }
        guard let low = RecoveryAnalytics.quantile(unwrapped, 0.25), let high = RecoveryAnalytics.quantile(unwrapped, 0.75) else { return nil }
        return WakeWindow(startMinutes: low.truncatingRemainder(dividingBy: 1440), endMinutes: high.truncatingRemainder(dividingBy: 1440), spreadMinutes: high - low)
    }
    /// Input must already be restricted to one source. Sleep dates follow local wake-up dates.
    public static func days(_ samples: [SleepInterval], calendar: Calendar = .current, now: Date = .now) -> [HealthDay] {
        let asleep = samples.filter { $0.stage != .awake && $0.stage != .inBed && $0.interval.duration > 0 }.sorted { $0.interval.start < $1.interval.start }
        var groups: [[SleepInterval]] = []
        var end: Date?
        for sample in asleep {
            if let end, sample.interval.start.timeIntervalSince(end) <= 90 * 60 { groups[groups.count - 1].append(sample) }
            else { groups.append([sample]) }
            end = max(end ?? sample.interval.end, sample.interval.end)
        }
        var rows: [Date: HealthDay] = [:], longest: [Date: Double] = [:]
        for group in groups {
            let wake = group.map { $0.interval.end }.max()!, date = calendar.startOfDay(for: wake)
            let total = RecoveryAnalytics.unionSeconds(group.map(\.interval))
            var row = rows[date] ?? HealthDay(date: date, updatedAt: now)
            if row.measurementDates == nil { row.measurementDates = [:] }
            let lastWake = max(row.measurementDates?["sleepHours"] ?? wake, wake)
            row.measurementDates?["sleepHours"] = lastWake
            row.sleepHours = (row.sleepHours ?? 0) + total / 3600
            // Segment at every boundary. General asleep is not added on top of stages.
            // Conflicting stage labels are counted in total sleep, but not invented as a stage.
            let boundaries = Set(group.flatMap { [$0.interval.start, $0.interval.end] }).sorted()
            var stages: [SleepInterval.Stage: Double] = [:]
            for (start, finish) in zip(boundaries, boundaries.dropFirst()) {
                let present = Set(group.filter { $0.interval.start < finish && $0.interval.end > start && $0.stage != .unspecified }.map(\.stage))
                if present.count == 1, let stage = present.first { stages[stage, default: 0] += finish.timeIntervalSince(start) }
            }
            for (stage, key) in [(SleepInterval.Stage.deep, \HealthDay.deepHours), (.core, \HealthDay.coreHours), (.rem, \HealthDay.remHours)] {
                if let seconds = stages[stage] { row[keyPath: key] = (row[keyPath: key] ?? 0) + seconds / 3600 }
            }
            if total > (longest[date] ?? 0) {
                longest[date] = total
                row.wakeMinutes = Double(calendar.component(.hour, from: wake) * 60 + calendar.component(.minute, from: wake))
            }
            rows[date] = row
        }
        return rows.values.sorted { $0.date < $1.date }
    }
}
