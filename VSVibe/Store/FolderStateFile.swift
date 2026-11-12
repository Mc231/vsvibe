import Foundation

/// Reads and writes `state.json` (`PersistedState`) for `FolderStore`.
internal enum FolderStateFile {
    /// Decodes the state at `url`. Returns nil when the file is missing or
    /// unreadable (both are logged), so the store starts empty. Label ids that
    /// no longer resolve (labels deleted out of band) are dropped from projects.
    internal static func read(from url: URL) -> PersistedState? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.store.info("No state file at \(url.path, privacy: .public), starting empty")
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var state = try decoder.decode(PersistedState.self, from: Data(contentsOf: url))
            let known = Set(state.labels.map(\.id))
            state.folders = state.folders.map { folder in
                var folder = folder
                folder.labelIDs = folder.labelIDs.filter { known.contains($0) }
                return folder
            }
            Log.store.info("Loaded \(state.folders.count) folders, \(state.labels.count) labels from disk")
            return state
        } catch {
            Log.store.error("Failed to load state: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Atomically writes `state` to `url`. Failures are logged, not thrown.
    internal static func write(_ state: PersistedState, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
            Log.store.debug("Saved state (\(data.count) bytes) to \(url.path, privacy: .public)")
        } catch {
            Log.store.error("Failed to save state: \(String(describing: error), privacy: .public)")
        }
    }
}
