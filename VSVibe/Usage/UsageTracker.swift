import Foundation

/// Watches a Claude transcript directory for a single pane and surfaces token
/// usage. Polls every `pollInterval` for new JSONL lines, parsing each
/// assistant message's `usage` block to maintain running totals + last context.
@MainActor
final class UsageTracker {
    let folderURL: URL
    let configDir: URL
    private let pollInterval: TimeInterval = 1.5
    private let onUpdate: (SessionUsage) -> Void

    private var timer: DispatchSourceTimer?
    private var currentTranscript: URL?
    private var fileOffset: UInt64 = 0
    private var partial = Data()
    private var usage = SessionUsage()

    init(folderURL: URL, configDir: URL, onUpdate: @escaping (SessionUsage) -> Void) {
        self.folderURL = folderURL
        self.configDir = configDir
        self.onUpdate = onUpdate
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: pollInterval)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
        guard let latest = TranscriptLocator.latestTranscript(in: projectDir) else { return }

        if currentTranscript != latest {
            // New session — reset state.
            currentTranscript = latest
            fileOffset = 0
            partial.removeAll()
            usage = SessionUsage()
        }

        let size = fileSize(latest)
        if size < fileOffset {
            fileOffset = 0
            partial.removeAll()
            usage = SessionUsage()
        }
        guard size > fileOffset else { return }

        guard let fh = try? FileHandle(forReadingFrom: latest) else { return }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: fileOffset) } catch { return }
        let chunk = fh.availableData
        fileOffset += UInt64(chunk.count)

        var buffer = partial + chunk
        partial.removeAll()

        var changed = false
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if applyLine(lineData) { changed = true }
        }
        partial = buffer

        if changed {
            usage.updatedAt = Date()
            onUpdate(usage)
        }
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Returns true if `usage` was modified.
    private func applyLine(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let type = obj["type"] as? String, type == "assistant" else { return false }
        guard let message = obj["message"] as? [String: Any] else { return false }

        let model = message["model"] as? String
        if let model { usage.lastModel = model }

        guard let usageDict = message["usage"] as? [String: Any] else { return false }
        let input = (usageDict["input_tokens"] as? Int) ?? 0
        let output = (usageDict["output_tokens"] as? Int) ?? 0
        let cacheC = (usageDict["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheR = (usageDict["cache_read_input_tokens"] as? Int) ?? 0

        usage.totalInput += input
        usage.totalOutput += output
        usage.totalCacheCreation += cacheC
        usage.totalCacheRead += cacheR
        usage.messageCount += 1
        // Approximate context size of this request = input side bytes.
        usage.lastContextTokens = input + cacheC + cacheR
        return true
    }
}
