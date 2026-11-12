import Foundation

/// Local-time `yyyy-MM-dd` day keys used to bucket stats. Keys sort
/// lexicographically in chronological order, so window filtering is a string
/// comparison.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func today() -> String {
        key(for: Date())
    }

    /// Earliest day key included in a window of `days` ending today.
    static func startKey(daysBack days: Int, now: Date = Date()) -> String {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        return key(for: start)
    }
}

// MARK: - Persisted model

/// Root persisted stats document. Keyed by a project's standardized folder path,
/// which is the common identifier across transcripts (path-encoded), git, and
/// runtime events.
struct StatsState: Codable {
    var version: Int = Self.currentVersion
    var projects: [String: ProjectStat] = [:]

    static let currentVersion = 1
}

/// All persisted stats for one project. Per-day buckets hold the time series;
/// `transcriptBytes` records how far each Claude transcript file has been
/// scanned so re-scans only read new bytes.
struct ProjectStat: Codable {
    var days: [String: DayStat] = [:]
    var transcriptBytes: [String: UInt64] = [:]
}

/// Additive metrics for a single local-time day (`yyyy-MM-dd`). Everything here
/// is summable across a window except `peakContextTokens` (max) and
/// `transcriptSessionIds` (union).
struct DayStat: Codable {
    // Claude usage (from transcripts).
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var costUSD: Double = 0
    var assistantMessages: Int = 0
    var toolCalls: Int = 0
    var modelMessageCounts: [String: Int] = [:]
    var peakContextTokens: Int = 0
    var highContextMessages: Int = 0
    var transcriptSessionIds: [String] = []

    // Session lifecycle (runtime).
    var panesOpened: Int = 0
    var activeSeconds: Double = 0

    // Hook activity (runtime).
    var notifications: Int = 0
    var finishes: Int = 0
    var subagentFinishes: Int = 0
}

// MARK: - Query types

enum StatWindow: String, CaseIterable, Identifiable {
    case today
    case last7
    case last30
    case allTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .last7: return "7 days"
        case .last30: return "30 days"
        case .allTime: return "All time"
        }
    }

    /// Number of days back the window spans, or nil for all-time.
    var days: Int? {
        switch self {
        case .today: return 1
        case .last7: return 7
        case .last30: return 30
        case .allTime: return nil
        }
    }
}

/// Aggregated Claude/lifecycle/hook metrics for a window. Git is computed
/// separately and lives in `GitStats`.
struct StatsSummary {
    var costUSD: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var assistantMessages: Int = 0
    var toolCalls: Int = 0
    var modelMessageCounts: [String: Int] = [:]
    var peakContextTokens: Int = 0
    var highContextMessages: Int = 0
    var distinctSessions: Int = 0

    var panesOpened: Int = 0
    var activeSeconds: Double = 0

    var notifications: Int = 0
    var finishes: Int = 0
    var subagentFinishes: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var peakContextPercent: Double {
        let window = 200_000.0
        return min(1.0, Double(peakContextTokens) / window) * 100
    }

    /// Model name → share of assistant messages (0...1), largest first.
    var modelShares: [(model: String, share: Double)] {
        let total = modelMessageCounts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return modelMessageCounts
            .map { ($0.key, Double($0.value) / Double(total)) }
            .sorted { $0.1 > $1.1 }
    }
}

/// On-demand git metrics. Commit/churn figures cover a trailing window; the rest
/// are current snapshots.
struct GitStats {
    var isRepo: Bool = false
    var currentBranch: String?
    var branchCount: Int = 0
    var commitsInWindow: Int = 0
    var linesAdded: Int = 0
    var linesRemoved: Int = 0
    var filesTouched: Int = 0
    var ahead: Int?
    var behind: Int?
    var lastCommitDate: Date?
    var lastCommitSubject: String?
    var windowDays: Int = 30
}
