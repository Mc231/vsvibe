import Foundation

/// Polling tail-watcher for `~/.vsvibe/events.jsonl`. New lines are decoded as
/// `HookEvent` and dispatched on the main actor.
@MainActor
final class EventWatcher {
    private let url: URL
    private let pollInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var offset: UInt64 = 0
    private var partialLine = Data()
    private let onEvent: (HookEvent) -> Void

    init(url: URL = HookInstaller.eventsFileURL,
         pollInterval: TimeInterval = 0.5,
         onEvent: @escaping (HookEvent) -> Void) {
        self.url = url
        self.pollInterval = pollInterval
        self.onEvent = onEvent
    }

    func start() {
        stop()
        ensureFileExists()
        offset = currentSize()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in
            self?.drain()
        }
        timer = t
        t.resume()
        Log.app.info("EventWatcher started at offset \(self.offset) for \(self.url.path, privacy: .public)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func ensureFileExists() {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
    }

    private func currentSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func drain() {
        let size = currentSize()
        if size < offset {
            // File was truncated or rotated — reset.
            offset = 0
            partialLine.removeAll()
        }
        guard size > offset else { return }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: offset)
        } catch {
            return
        }
        let chunk = fh.availableData
        offset += UInt64(chunk.count)

        var buffer = partialLine + chunk
        partialLine.removeAll()

        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let event = parseLine(lineData) {
                onEvent(event)
            }
        }
        partialLine = buffer
    }

    private func parseLine(_ data: Data) -> HookEvent? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(HookEvent.self, from: data)
        } catch {
            let str = String(data: data, encoding: .utf8) ?? "<binary>"
            Log.app.error("EventWatcher: failed to parse line: \(str, privacy: .public) error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
