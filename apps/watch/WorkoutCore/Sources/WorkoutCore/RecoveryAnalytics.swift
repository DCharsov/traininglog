import Foundation

/// Local-only domain types. Never inserted into Session JSON or network requests.
public struct HealthDay: Codable, Identifiable, Equatable, Sendable {
    public var date: Date
    public var sleepHours: Double?
    public var restingPulse: Double?
    public var hrvMS: Double?
    public var weightKG: Double?
    public var deepHours: Double?
    public var remHours: Double?
    public var coreHours: Double?
    public var wakeMinutes: Double?
    public var updatedAt: Date
    /// Actual measurement times, not the date when the local cache was refreshed.
    public var measurementDates: [String: Date]?
    public var id: Date { date }
    public init(date: Date, sleepHours: Double? = nil, restingPulse: Double? = nil, hrvMS: Double? = nil, weightKG: Double? = nil, updatedAt: Date) {
        self.date = date; self.sleepHours = sleepHours; self.restingPulse = restingPulse; self.hrvMS = hrvMS; self.weightKG = weightKG; self.updatedAt = updatedAt
    }
}
public struct RecoveryAssessment: Equatable, Sendable {
    public let status: String
    public let factors: [String]
    public let usableMetrics: Int
    public var comparisons: [RecoveryComparison] = []
    public var date: Date? = nil
}
public struct RecoveryComparison: Equatable, Sendable, Identifiable {
    public let id: String
    public let unit: String
    public let value: Double
    public let threshold: Double
    public let baselineDays: Int
    public let upperQuartile: Bool
    public let unfavorable: Bool
}
public enum RecoveryAnalytics {
    public static func unionSeconds(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total = 0.0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end { current = DateInterval(start: current.start, end: max(current.end, interval.end)) }
            else { total += current.duration; current = interval }
        }
        return total + current.duration
    }
    public static func quantile(_ values: [Double], _ fraction: Double) -> Double? {
        let values = values.filter(\.isFinite).sorted()
        guard !values.isEmpty else { return nil }
        let index = Double(values.count - 1) * min(1, max(0, fraction)), lower = Int(index)
        return values[lower] + (values[min(lower + 1, values.count - 1)] - values[lower]) * (index - Double(lower))
    }
    public static func assess(days: [HealthDay], feeling: Int?, now: Date, calendar: Calendar = .current) -> RecoveryAssessment {
        // A baseline is counted in distinct local days, never in number of imported rows.
        let days = Dictionary(grouping: days, by: { calendar.startOfDay(for: $0.date) }).compactMap { date, rows -> HealthDay? in
            guard var row = rows.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
            row.date = date; return row
        }
        let today = calendar.startOfDay(for: now)
        guard let target = days.filter({ $0.date < today }).max(by: { $0.date < $1.date }) else {
            return RecoveryAssessment(status: "Недостаточно данных", factors: [], usableMetrics: 0)
        }
        let start = calendar.date(byAdding: .day, value: -28, to: target.date)!
        let baseline = days.filter { $0.date >= start && $0.date < target.date }
        let definitions: [(String, String, String, String, KeyPath<HealthDay, Double?>, Bool)] = [("Сон короче обычного", "Сон", "sleepHours", "ч", \.sleepHours, false), ("HRV ниже обычного", "HRV", "hrvMS", "мс", \.hrvMS, false), ("Пульс покоя выше обычного", "Пульс покоя", "restingPulse", "уд/мин", \.restingPulse, true)]
        var factors: [String] = [], usable = 0
        var comparisons: [RecoveryComparison] = []
        for (label, name, metric, unit, key, upper) in definitions {
            // Old local rows without timestamps are treated conservatively using
            // midnight, never updatedAt (a refresh must not make old data fresh).
            let measuredAt = target.measurementDates?[metric] ?? target.date
            let age = now.timeIntervalSince(measuredAt)
            guard age >= 0, age <= 48 * 3600, calendar.startOfDay(for: measuredAt) == target.date else { continue }
            let values = baseline.compactMap { $0[keyPath: key] }.filter { $0.isFinite && $0 > 0 }
            guard values.count >= 14, let value = target[keyPath: key], value.isFinite, value > 0,
                  let threshold = quantile(values, upper ? 0.75 : 0.25) else { continue }
            usable += 1
            let unfavorable = upper ? value > threshold : value < threshold
            comparisons.append(RecoveryComparison(id: name, unit: unit, value: value, threshold: threshold, baselineDays: values.count, upperQuartile: upper, unfavorable: unfavorable))
            if unfavorable { factors.append(label) }
        }
        let lowFeeling = feeling.map { (1...2).contains($0) } ?? false
        let unfavorable = factors.count
        if lowFeeling { factors.append("Вы отметили низкое самочувствие") }
        let status = usable < 2 ? "Недостаточно данных" : unfavorable >= 2 || lowFeeling ? "Стоит рассмотреть более лёгкую тренировку" : "Без выраженных отклонений от вашей обычной картины"
        return RecoveryAssessment(status: status, factors: factors, usableMetrics: usable, comparisons: comparisons, date: target.date)
    }
}
