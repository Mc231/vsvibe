import Foundation

/// Polling tail-watcher for `~/.vsvibe/events.jsonl`. New lines are decoded as
/// `HookEvent` and dispatched on the main actor.
@MainActor
internal final class EventWatcher {
    private enum Constants {
        static let defaultPollInterval: TimeInterval = 0.5
        static let newline: UInt8 = 0x0A
    }

    private let url: URL
    private let pollInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var offset: UInt64 = 0
    private var partialLine = Data()
    private let onEvent: (HookEvent) -> Void

    /// Whether the poll timer is running.
    internal var isRunning: Bool { timer != nil }

    internal init(
        url: URL = HookInstaller.eventsFileURL,
        pollInterval: TimeInterval = Constants.defaultPollInterval,
        onEvent: @escaping (HookEvent) -> Void
    ) {
        self.url = url
        self.pollInterval = pollInterval
        self.onEvent = onEvent
    }

    /// Starts tailing from the current end of the file (existing lines are skipped).
    internal func start() {
        stop()
        ensureFileExists()
        offset = currentSize()
        let pollTimer = DispatchSource.makeTimerSource(queue: .main)
        pollTimer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        pollTimer.setEventHandler { [weak self] in
            self?.drain()
        }
        timer = pollTimer
        pollTimer.resume()
        Log.app.info("EventWatcher started at offset \(self.offset) for \(self.url.path, privacy: .public)")
    }

    internal func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Reads everything appended since the last call and dispatches each
    /// complete line. A trailing line without a newline is kept for the next
    /// call; a file that shrank (truncated or rotated) is re-read from the start.
    internal func drain() {
        let size = currentSize()
        if size < offset {
            // File was truncated or rotated — reset.
            offset = 0
            partialLine.removeAll()
        }
        guard size > offset else {
            return
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return
        }
        let chunk = handle.availableData
        offset += UInt64(chunk.count)

        var buffer = partialLine + chunk
        partialLine.removeAll()

        while let newlineIndex = buffer.firstIndex(of: Constants.newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if let event = parseLine(lineData) {
                onEvent(event)
            }
        }
        partialLine = buffer
    }

    private func ensureFileExists() {
        let fileManager = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
    }

    private func currentSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    private func parseLine(_ data: Data) -> HookEvent? {
        guard !data.isEmpty else {
            return nil
        }
        do {
            return try JSONDecoder().decode(HookEvent.self, from: data)
        } catch {
            let text = String(bytes: data, encoding: .utf8) ?? "<binary>"
            let detail = "failed to parse line: \(text) error=\(String(describing: error))"
            Log.app.error("EventWatcher: \(detail, privacy: .public)")
            return nil
        }
    }

    deinit {
        // The timer handler captures self weakly; nothing else to release.
    }
}
