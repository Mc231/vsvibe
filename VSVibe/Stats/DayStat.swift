/// Additive metrics for a single local-time day (`yyyy-MM-dd`). Everything here
/// is summable across a window except `peakContextTokens` (max) and
/// `transcriptSessionIds` (union).
internal struct DayStat: Codable {
    // Claude usage (from transcripts).
    internal var inputTokens: Int = 0
    internal var outputTokens: Int = 0
    internal var cacheCreationTokens: Int = 0
    internal var cacheReadTokens: Int = 0
    internal var costUSD: Double = 0
    internal var assistantMessages: Int = 0
    internal var toolCalls: Int = 0
    internal var modelMessageCounts: [String: Int] = [:]
    internal var peakContextTokens: Int = 0
    internal var highContextMessages: Int = 0
    internal var transcriptSessionIds: [String] = []

    // Session lifecycle (runtime).
    internal var panesOpened: Int = 0
    internal var activeSeconds: Double = 0

    // Hook activity (runtime).
    internal var notifications: Int = 0
    internal var finishes: Int = 0
    internal var subagentFinishes: Int = 0
}
