import Foundation

/// Running token usage of one Claude transcript, fed with its bytes in any
/// chunking: complete JSONL lines are parsed, each assistant message's `usage`
/// block adds to the totals and sets the last context size. Pure; used by the
/// local `TranscriptUsageReader` (file chunks) and remote usage (ssh stream).
internal struct UsageAccumulator {
    internal private(set) var usage = SessionUsage()
    private var lines = LineSplitter()

    /// Feeds `chunk`; returns the usage (stamped `now`) when a line completed
    /// by it changed the totals, else nil.
    internal mutating func consume(_ chunk: Data, now: Date = Date()) -> SessionUsage? {
        var changed = false
        for line in lines.append(chunk) where apply(line) {
            changed = true
        }
        guard changed else {
            return nil
        }
        usage.updatedAt = now
        return usage
    }

    /// Returns true if `usage` was modified.
    private mutating func apply(_ data: Data) -> Bool {
        guard !data.isEmpty,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = obj["type"] as? String,
            type == "assistant",
            let message = obj["message"] as? [String: Any]
        else {
            return false
        }

        if let model = message["model"] as? String {
            usage.lastModel = model
        }

        guard let usageDict = message["usage"] as? [String: Any] else {
            return false
        }
        let input = (usageDict["input_tokens"] as? Int) ?? 0
        let output = (usageDict["output_tokens"] as? Int) ?? 0
        let cacheCreation = (usageDict["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usageDict["cache_read_input_tokens"] as? Int) ?? 0

        usage.totalInput += input
        usage.totalOutput += output
        usage.totalCacheCreation += cacheCreation
        usage.totalCacheRead += cacheRead
        usage.messageCount += 1
        // Approximate context size of this request = input side bytes.
        usage.lastContextTokens = input + cacheCreation + cacheRead
        return true
    }
}
