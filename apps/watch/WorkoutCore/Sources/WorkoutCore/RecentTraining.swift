import Foundation

/// Completed diary days in today and the previous six local calendar days.
/// Identity, not a translated day name, links the result to its program.
public enum RecentTraining {
    public static func lastDate(sessions: [JSONValue], programID: String, dayID: String,
                                now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard !programID.isEmpty, !dayID.isEmpty,
              let first = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return nil }
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        format.isLenient = false
        let lower = format.string(from: first), upper = format.string(from: now)
        return sessions.compactMap { session -> String? in
            guard session["programId"].string?.lowercased() == programID.lowercased(),
                  session["dayId"].string?.lowercased() == dayID.lowercased(),
                  session["status"].string == "completed", session["deletedAt"] == .null,
                  session["exercises"].array.contains(where: { $0["records"].array.contains { $0["status"].string == "completed" } }),
                  let date = session["localDate"].string, date >= lower, date <= upper,
                  let parsed = format.date(from: date), format.string(from: parsed) == date else { return nil }
            return date
        }.max()
    }
}
