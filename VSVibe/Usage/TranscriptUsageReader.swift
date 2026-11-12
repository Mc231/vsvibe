import Foundation

/// Mutable parsing state belongs to one background polling task, never the UI.
internal struct TranscriptUsageReader {
    private enum Constants {
        static let newline: UInt8 = 0x0A
    }

    /// Default number of bytes read per poll (256 KiB).
    internal static let defaultChunkSize = 262_144

    internal let folderURL: URL
    internal let configDir: URL
    internal var chunkSize: Int
    internal private(set) var hasMoreData = false
    private var currentTranscript: URL?
    private var fileOffset: UInt64 = 0
    private var partial = Data()
    private var usage = SessionUsage()

    internal init(folderURL: URL, configDir: URL, chunkSize: Int = defaultChunkSize) {
        self.folderURL = folderURL
        self.configDir = configDir
        self.chunkSize = chunkSize
    }

    internal mutating func poll() -> SessionUsage? {
        hasMoreData = false
        let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
        guard let latest = TranscriptLocator.latestTranscript(in: projectDir) else {
            return nil
        }

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
        guard size > fileOffset else {
            return nil
        }
        guard let chunk = readChunk(of: latest) else {
            return nil
        }
        fileOffset += UInt64(chunk.count)

        hasMoreData = fileOffset < size
        let buffer = partial + chunk
        var lineStart = buffer.startIndex

        var changed = false
        for index in buffer.indices where buffer[index] == Constants.newline {
            if applyLine(buffer.subdata(in: lineStart..<index)) {
                changed = true
            }
            lineStart = index + 1
        }
        partial = Data(buffer[lineStart...])

        if changed {
            usage.updatedAt = Date()
            return usage
        }
        return nil
    }

    /// Next non-empty chunk of `url` from `fileOffset`, or nil on error / EOF.
    private func readChunk(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: fileOffset)
        } catch {
            return nil
        }
        guard let chunk = try? handle.read(upToCount: max(1, chunkSize)), !chunk.isEmpty else {
            return nil
        }
        return chunk
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    /// Returns true if `usage` was modified.
    private mutating func applyLine(_ data: Data) -> Bool {
        guard !data.isEmpty else {
            return false
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let type = obj["type"] as? String, type == "assistant" else {
            return false
        }
        guard let message = obj["message"] as? [String: Any] else {
            return false
        }

        let model = message["model"] as? String
        if let model {
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
