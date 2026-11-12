/// Aggregated Claude/lifecycle/hook metrics for a window. Git is computed
/// separately and lives in `GitStats`.
internal struct StatsSummary {
    private enum Constants {
        static let contextWindowTokens = 200_000.0
        static let percentScale = 100.0
    }

    internal var costUSD: Double = 0
    internal var inputTokens: Int = 0
    internal var outputTokens: Int = 0
    internal var cacheCreationTokens: Int = 0
    internal var cacheReadTokens: Int = 0
    internal var assistantMessages: Int = 0
    internal var toolCalls: Int = 0
    internal var modelMessageCounts: [String: Int] = [:]
    internal var peakContextTokens: Int = 0
    internal var highContextMessages: Int = 0
    internal var distinctSessions: Int = 0

    internal var panesOpened: Int = 0
    internal var activeSeconds: Double = 0

    internal var notifications: Int = 0
    internal var finishes: Int = 0
    internal var subagentFinishes: Int = 0

    internal var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    internal var peakContextPercent: Double {
        min(1.0, Double(peakContextTokens) / Constants.contextWindowTokens) * Constants.percentScale
    }

    /// Model name → share of assistant messages (0...1), largest first.
    internal var modelShares: [(model: String, share: Double)] {
        let total = modelMessageCounts.values.reduce(0, +)
        guard total > 0 else {
            return []
        }
        return modelMessageCounts
            .map { ($0.key, Double($0.value) / Double(total)) }
            .sorted { $0.1 > $1.1 }
    }
}
