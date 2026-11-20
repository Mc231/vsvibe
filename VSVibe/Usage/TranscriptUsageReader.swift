import Foundation

/// Mutable parsing state belongs to one background polling task, never the UI.
internal struct TranscriptUsageReader {
    /// Default number of bytes read per poll (256 KiB).
    internal static let defaultChunkSize = 262_144

    internal let source: TranscriptSource
    internal var chunkSize: Int
    internal private(set) var hasMoreData = false
    private var currentTranscript: URL?
    private var fileOffset: UInt64 = 0
    private var accumulator = UsageAccumulator()

    internal init(source: TranscriptSource, chunkSize: Int = defaultChunkSize) {
        self.source = source
        self.chunkSize = chunkSize
    }

    internal mutating func poll() -> SessionUsage? {
        hasMoreData = false
        guard let latest = source.currentTranscript() else {
            return nil
        }

        if currentTranscript != latest {
            // New session — reset state.
            currentTranscript = latest
            fileOffset = 0
            accumulator = UsageAccumulator()
        }

        let size = fileSize(latest)
        if size < fileOffset {
            fileOffset = 0
            accumulator = UsageAccumulator()
        }
        guard size > fileOffset else {
            return nil
        }
        guard let chunk = readChunk(of: latest) else {
            return nil
        }
        fileOffset += UInt64(chunk.count)

        hasMoreData = fileOffset < size
        return accumulator.consume(chunk)
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
}
