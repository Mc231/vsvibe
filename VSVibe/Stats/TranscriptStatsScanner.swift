import Foundation

/// Folds Claude transcript JSONL into per-day `DayStat` buckets. Scanning is
/// incremental: each transcript file's consumed byte offset is recorded in
/// `ProjectStat.transcriptBytes`, so repeat scans only read newly-appended
/// lines. Pure and `nonisolated` — safe to run off the main thread.
enum TranscriptStatsScanner {
    private static let highContextThreshold = 0.85
    private static let contextWindow = 200_000.0

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Scans every transcript for `folderURL` across the given Claude config
    /// dirs, folding new bytes into `stat`. Returns true if anything changed.
    @discardableResult
    static func scan(into stat: inout ProjectStat, folderURL: URL, configDirs: [URL]) -> Bool {
        let fm = FileManager.default
        var changed = false
        for configDir in configDirs {
            let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
            guard let entries = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in entries where file.pathExtension == "jsonl" {
                if scanFile(file, into: &stat) { changed = true }
            }
        }
        return changed
    }

    private static func scanFile(_ file: URL, into stat: inout ProjectStat) -> Bool {
        // Transcript filenames are session UUIDs, so they're globally unique.
        let key = file.lastPathComponent
        var offset = stat.transcriptBytes[key] ?? 0
        let size = fileSize(file)
        if size < offset { offset = 0 } // file was rotated/truncated
        guard size > offset else { return false }

        guard let fh = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: offset) } catch { return false }
        let data = fh.readDataToEndOfFile()

        // Consume only through the last complete line; leave any trailing
        // partial line for the next scan.
        guard let lastNL = data.lastIndex(of: 0x0A) else { return false }
        let consumable = data.subdata(in: data.startIndex..<(lastNL + 1))

        var changed = false
        var cursor = consumable.startIndex
        while let nl = consumable[cursor...].firstIndex(of: 0x0A) {
            let line = consumable.subdata(in: cursor..<nl)
            if applyLine(line, into: &stat) { changed = true }
            cursor = consumable.index(after: nl)
        }
        stat.transcriptBytes[key] = offset + UInt64(consumable.count)
        return changed
    }

    private static func applyLine(_ data: Data, into stat: inout ProjectStat) -> Bool {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let message = obj["message"] as? [String: Any] else { return false }

        let dayKey: String
        if let ts = obj["timestamp"] as? String, let date = parseISO(ts) {
            dayKey = DayKey.key(for: date)
        } else {
            dayKey = DayKey.today()
        }

        var day = stat.days[dayKey] ?? DayStat()

        let model = message["model"] as? String
        let usage = message["usage"] as? [String: Any] ?? [:]
        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheC = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheR = (usage["cache_read_input_tokens"] as? Int) ?? 0

        day.inputTokens += input
        day.outputTokens += output
        day.cacheCreationTokens += cacheC
        day.cacheReadTokens += cacheR
        day.assistantMessages += 1

        var msgUsage = SessionUsage()
        msgUsage.totalInput = input
        msgUsage.totalOutput = output
        msgUsage.totalCacheCreation = cacheC
        msgUsage.totalCacheRead = cacheR
        day.costUSD += ModelPricing.cost(model: model, usage: msgUsage)

        if let model { day.modelMessageCounts[model, default: 0] += 1 }

        let contextTokens = input + cacheC + cacheR
        day.peakContextTokens = max(day.peakContextTokens, contextTokens)
        if Double(contextTokens) / contextWindow >= highContextThreshold {
            day.highContextMessages += 1
        }

        if let content = message["content"] as? [[String: Any]] {
            day.toolCalls += content.reduce(0) { $0 + (($1["type"] as? String) == "tool_use" ? 1 : 0) }
        }

        if let sid = obj["sessionId"] as? String, !day.transcriptSessionIds.contains(sid) {
            day.transcriptSessionIds.append(sid)
        }

        stat.days[dayKey] = day
        return true
    }

    private static func parseISO(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
