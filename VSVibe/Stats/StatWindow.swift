internal enum StatWindow: CaseIterable, Identifiable {
    case allTime
    case last30
    case last7
    case today

    private enum Constants {
        static let weekDays = 7
        static let monthDays = 30
    }

    /// Display order (shortest window first); cases are declared alphabetically.
    internal static let allCases: [Self] = [.today, .last7, .last30, .allTime]

    /// Stable identifier: the case name (`"today"`, `"last7"`, ...).
    internal var id: String { String(describing: self) }

    internal var label: String {
        switch self {
        case .today:
            return "Today"

        case .last7:
            return "7 days"

        case .last30:
            return "30 days"

        case .allTime:
            return "All time"
        }
    }

    /// Number of days back the window spans, or nil for all-time.
    internal var days: Int? {
        switch self {
        case .today:
            return 1

        case .last7:
            return Constants.weekDays

        case .last30:
            return Constants.monthDays

        case .allTime:
            return nil
        }
    }
}
