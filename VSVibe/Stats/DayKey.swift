import Foundation

/// Local-time `yyyy-MM-dd` day keys used to bucket stats. Keys sort
/// lexicographically in chronological order, so window filtering is a string
/// comparison.
internal enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    internal static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    internal static func today() -> String {
        key(for: Date())
    }

    /// Earliest day key included in a window of `days` ending today.
    internal static func startKey(daysBack days: Int, now: Date = Date()) -> String {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return key(for: start)
    }
}
