import Foundation

/// Reads, writes and removes `sessions.json` (`SessionSnapshot`).
internal enum SessionSnapshotFile {
    /// Decodes the snapshot at `url`. Returns nil when the file is missing or
    /// unreadable (logged), so nothing is restored.
    internal static func read(from url: URL) -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: url))
            Log.store.info("Loaded \(snapshot.panes.count) panes to restore")
            return snapshot
        } catch {
            Log.store.error("Failed to load sessions: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Atomically writes `snapshot` to `url`. Failures are logged, not thrown.
    internal static func write(_ snapshot: SessionSnapshot, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: [.atomic])
        } catch {
            Log.store.error("Failed to save sessions: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the file if present (restore turned off: nothing to keep).
    internal static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
