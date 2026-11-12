import Foundation

/// Folds Claude transcript JSONL into per-day `DayStat` buckets. Scanning is
/// incremental: each transcript file's consumed byte offset is recorded in
/// `ProjectStat.transcriptBytes`, so repeat scans only read newly-appended
/// lines. Pure and `nonisolated` — safe to run off the main thread.
internal enum TranscriptStatsScanner {
    private enum Constants {
        static let newline: UInt8 = 0x0A
    }

    private static let highContextThreshold = 0.85
    private static let contextWindow = 200_000.0

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Scans every transcript for `folderURL` across the given Claude config
    /// dirs, folding new bytes into `stat`. Returns true if anything changed.
    @discardableResult
    internal static func scan(into stat: inout ProjectStat, folderURL: URL, configDirs: [URL]) -> Bool {
        let fileManager = FileManager.default
        var changed = false
        for configDir in configDirs {
            let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in entries where file.pathExtension == "jsonl" {
                if scanFile(file, into: &stat) {
                    changed = true
                }
            }
        }
        return changed
    }

    private static func scanFile(_ file: URL, into stat: inout ProjectStat) -> Bool {
        // Transcript filenames are session UUIDs, so they're globally unique.
        let key = file.lastPathComponent
        var offset = stat.transcriptBytes[key] ?? 0
        let size = fileSize(file)
        if size < offset {
            offset = 0 // file was rotated/truncated
        }
        guard size > offset else {
            return false
        }
        guard let data = readToEnd(of: file, from: offset) else {
            return false
        }

        // Consume only through the last complete line; leave any trailing
        // partial line for the next scan.
        guard let lastNewline = data.lastIndex(of: Constants.newline) else {
            return false
        }
        let consumable = data.subdata(in: data.startIndex..<(lastNewline + 1))

        var changed = false
        var cursor = consumable.startIndex
        while let newline = consumable[cursor...].firstIndex(of: Constants.newline) {
            let line = consumable.subdata(in: cursor..<newline)
            if applyLine(line, into: &stat) {
                changed = true
            }
            cursor = consumable.index(after: newline)
        }
        stat.transcriptBytes[key] = offset + UInt64(consumable.count)
        return changed
    }

    private static func applyLine(_ data: Data, into stat: inout ProjectStat) -> Bool {
        guard !data.isEmpty else {
            return false
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard (obj["type"] as? String) == "assistant", let message = obj["message"] as? [String: Any] else {
            return false
        }

        let dayKey: String
        if let timestamp = obj["timestamp"] as? String, let date = parseISO(timestamp) {
            dayKey = DayKey.key(for: date)
        } else {
            dayKey = DayKey.today()
        }

        var day = stat.days[dayKey] ?? DayStat()

        let model = message["model"] as? String
        let usage = message["usage"] as? [String: Any] ?? [:]
        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreation = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        day.inputTokens += input
        day.outputTokens += output
        day.cacheCreationTokens += cacheCreation
        day.cacheReadTokens += cacheRead
        day.assistantMessages += 1

        var msgUsage = SessionUsage()
        msgUsage.totalInput = input
        msgUsage.totalOutput = output
        msgUsage.totalCacheCreation = cacheCreation
        msgUsage.totalCacheRead = cacheRead
        day.costUSD += ModelPricing.cost(model: model, usage: msgUsage)

        if let model {
            day.modelMessageCounts[model, default: 0] += 1
        }

        let contextTokens = input + cacheCreation + cacheRead
        day.peakContextTokens = max(day.peakContextTokens, contextTokens)
        if Double(contextTokens) / contextWindow >= highContextThreshold {
            day.highContextMessages += 1
        }

        if let content = message["content"] as? [[String: Any]] {
            day.toolCalls += content.reduce(0) { $0 + (($1["type"] as? String) == "tool_use" ? 1 : 0) }
        }

        if let sessionId = obj["sessionId"] as? String, !day.transcriptSessionIds.contains(sessionId) {
            day.transcriptSessionIds.append(sessionId)
        }

        stat.days[dayKey] = day
        return true
    }

    private static func parseISO(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    /// Remaining bytes of `file` from `offset`, or nil when it can't be read.
    private static func readToEnd(of file: URL, from offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        return handle.readDataToEndOfFile()
    }
}
