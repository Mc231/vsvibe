import Foundation

/// Owns one `UsageTracker` per pane and keeps it pointed at the right
/// transcript: the pane's own conversation once a hook event reported its
/// path (retargeted when it changes, e.g. after `/clear`), before that the
/// folder's latest transcript under the launch command's alias.
@MainActor
internal final class PaneUsageTracking {
    internal private(set) var trackers: [TerminalSession.ID: UsageTracker] = [:]
    /// Config dir of each pane's launch-command alias (absent: none).
    private var fallbackConfigDirs: [TerminalSession.ID: URL] = [:]

    internal init() {
        // Trackers are added per pane by start(_:fallbackConfigDir:).
    }

    /// Starts tracking a new pane.
    internal func start(_ session: TerminalSession, fallbackConfigDir: URL?) {
        fallbackConfigDirs[session.id] = fallbackConfigDir
        refresh(session)
    }

    /// Points the pane's tracker at `TranscriptSource.select(…)` for its current
    /// transcript path. A different source restarts the tracker and clears
    /// the shown usage (it belonged to another conversation); no source stops it.
    internal func refresh(_ session: TerminalSession) {
        let source = TranscriptSource.select(
            transcriptPath: session.claudeTranscriptPath,
            fallbackConfigDir: fallbackConfigDirs[session.id],
            folderURL: session.folder.url
        )
        let current = trackers[session.id]
        guard current?.source != source else {
            return
        }
        if let current {
            current.stop()
            trackers[session.id] = nil
            session.usage = nil
        }
        guard let source else {
            return
        }
        let tracker = UsageTracker(source: source) { [weak session] usage in
            session?.usage = usage
        }
        trackers[session.id] = tracker
        tracker.start()
    }

    internal func stop(id: TerminalSession.ID) {
        trackers[id]?.stop()
        trackers[id] = nil
        fallbackConfigDirs[id] = nil
    }

    internal func stopAll() {
        for tracker in trackers.values {
            tracker.stop()
        }
        trackers.removeAll()
        fallbackConfigDirs.removeAll()
    }

    deinit {
        // Trackers are stopped explicitly by SessionManager; each cancels its task on deinit.
    }
}
