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

    private var pollingTask: Task<Void, Never>?
    private var generation = UUID()

    init(folderURL: URL, configDir: URL, onUpdate: @escaping (SessionUsage) -> Void) {
        self.folderURL = folderURL
        self.configDir = configDir
        self.onUpdate = onUpdate
    }

    func start() {
        stop()
        let generation = generation
        let folder = folderURL
        let config = configDir
        let interval = UInt64(pollInterval * 1_000_000_000)
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            var reader = TranscriptUsageReader(folderURL: folder, configDir: config)
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                while !Task.isCancelled {
                    let update = reader.poll()
                    if let update {
                        await self?.publish(update, generation: generation)
                    }
                    // Catch up in bounded chunks without making the UI wait.
                    try await Task.sleep(nanoseconds: reader.hasMoreData ? 10_000_000 : interval)
                }
            } catch { /* Cancellation ends polling. */ }
        }
    }

    func stop() {
        generation = UUID()
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func publish(_ usage: SessionUsage, generation: UUID) {
        guard self.generation == generation else { return }
        onUpdate(usage)
    }

    deinit { pollingTask?.cancel() }
}

/// Mutable parsing state belongs to one background polling task, never the UI.
struct TranscriptUsageReader {
    let folderURL: URL
    let configDir: URL
    var chunkSize = 256 * 1_024
    private(set) var hasMoreData = false
    private var currentTranscript: URL?
    private var fileOffset: UInt64 = 0
    private var partial = Data()
    private var usage = SessionUsage()

    init(folderURL: URL, configDir: URL, chunkSize: Int = 256 * 1_024) {
        self.folderURL = folderURL
        self.configDir = configDir
        self.chunkSize = chunkSize
    }

    mutating func poll() -> SessionUsage? {
        hasMoreData = false
        let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
        guard let latest = TranscriptLocator.latestTranscript(in: projectDir) else { return nil }

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
        guard size > fileOffset else { return nil }

        guard let fh = try? FileHandle(forReadingFrom: latest) else { return nil }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: fileOffset) } catch { return nil }
        guard let chunk = try? fh.read(upToCount: max(1, chunkSize)), !chunk.isEmpty else { return nil }
        fileOffset += UInt64(chunk.count)

        hasMoreData = fileOffset < size
        let buffer = partial + chunk
        var lineStart = buffer.startIndex

        var changed = false
        for index in buffer.indices where buffer[index] == 0x0A {
            if applyLine(buffer.subdata(in: lineStart..<index)) { changed = true }
            lineStart = index + 1
        }
        partial = Data(buffer[lineStart...])

        if changed {
            usage.updatedAt = Date()
            return usage
        }
        return nil
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Returns true if `usage` was modified.
    private mutating func applyLine(_ data: Data) -> Bool {
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
