import Foundation

/// Reads, writes and removes `sessions.json` (`SessionSnapshot`).
internal enum SessionSnapshotFile {
    /// Only the version, checked before decoding the rest.
    private struct Header: Decodable {
        let version: Int
    }

    /// Decodes the snapshot at `url`. Returns nil when the file is missing,
    /// unreadable or written by a newer VSVibe (`version` above
    /// `SessionSnapshot.currentVersion`; logged), so nothing is restored.
    internal static func read(from url: URL) -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version <= SessionSnapshot.currentVersion else {
                Log.store.error("Not restoring sessions: file version \(version) is newer than supported")
                return nil
            }
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
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
