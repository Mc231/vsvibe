import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
internal final class SessionManager {
    internal private(set) var sessions: [TerminalSession] = []
    internal var focusedSessionID: TerminalSession.ID?

    @ObservationIgnored private var processDelegates: [TerminalSession.ID: SessionProcessDelegate] = [:]
    @ObservationIgnored private let usageTracking = PaneUsageTracking()
    @ObservationIgnored private var gitTrackers: [TerminalSession.ID: GitBranchTracker] = [:]
    @ObservationIgnored private var openedAt: [TerminalSession.ID: Date] = [:]
    @ObservationIgnored private let statsStore: StatsStore
    @ObservationIgnored private let aliasStore: LaunchAliasStore
    @ObservationIgnored private let launcher: SessionLauncher

    /// The running usage tracker of each pane that has one.
    internal var usageTrackers: [TerminalSession.ID: UsageTracker] { usageTracking.trackers }

    /// The open panes (in order) and focus, as persisted for restore on launch.
    internal var snapshot: SessionSnapshot {
        SessionSnapshot(
            panes: sessions.map { session in
                PaneSnapshot(
                    folderID: session.folder.id,
                    claudeSessionID: session.claudeSessionID,
                    transcriptPath: session.claudeTranscriptPath
                )
            },
            focusedIndex: focusedSessionID.flatMap { id in sessions.firstIndex { $0.id == id } }
        )
    }

    internal init(statsStore: StatsStore, aliasStore: LaunchAliasStore, launcher: SessionLauncher? = nil) {
        self.aliasStore = aliasStore
        self.statsStore = statsStore
        self.launcher = launcher ?? .live
    }

    internal func ensureSession(for folder: FolderEntry, commandOverride: String? = nil) {
        if hasSession(forFolder: folder.id) {
            return
        }
        _ = makeSession(for: folder, commandOverride: commandOverride)
    }

    /// Always creates a new session for `folder` (allowing multiple panes per
    /// folder). The new session takes focus. Returns the freshly created session.
    @discardableResult
    internal func createSession(for folder: FolderEntry) -> TerminalSession {
        let session = makeSession(for: folder)
        focusedSessionID = session.id
        return session
    }

    /// Opens a pane restored from a previous launch: `command` is typed instead
    /// of the folder's launch command (e.g. `claude --resume <id>`) and the
    /// Claude conversation id and transcript path are carried over, so a later
    /// relaunch resumes it again. Focus is left to the caller.
    @discardableResult
    internal func restoreSession(
        for folder: FolderEntry,
        command: String,
        claudeSessionID: String?,
        transcriptPath: String? = nil
    ) -> TerminalSession {
        let session = makeSession(for: folder, commandOverride: command)
        recordClaudeConversation(claudeSessionID, transcriptPath: transcriptPath, in: session)
        return session
    }

    /// Records the Claude conversation running in `session` (from its hook
    /// events or a restore) and points the pane's usage tracker at that
    /// conversation's transcript (or back at the launch alias's latest one
    /// when the path is unknown). Ignored for usage when the pane is closed.
    internal func recordClaudeConversation(
        _ claudeSessionID: String?,
        transcriptPath: String?,
        in session: TerminalSession
    ) {
        session.claudeSessionID = claudeSessionID
        session.claudeTranscriptPath = transcriptPath
        if sessions.contains(where: { $0.id == session.id }) {
            usageTracking.refresh(session)
        }
    }

    internal func hasSession(forFolder folderID: FolderEntry.ID) -> Bool {
        sessions.contains { $0.folder.id == folderID }
    }

    internal func sessions(forFolder folderID: FolderEntry.ID) -> [TerminalSession] {
        sessions.filter { $0.folder.id == folderID }
    }

    internal func firstSession(forFolder folderID: FolderEntry.ID) -> TerminalSession? {
        sessions.first { $0.folder.id == folderID }
    }

    internal func closeAllSessions(forFolder folderID: FolderEntry.ID) {
        for session in sessions(forFolder: folderID) {
            closeSession(id: session.id)
        }
    }

    internal func closeSession(id: TerminalSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else {
            return
        }
        recordActiveTime(for: session)
        session.terminalView.processDelegate = nil
        terminate(session: session)
        usageTracking.stop(id: id)
        gitTrackers[id]?.stop()
        gitTrackers[id] = nil
        openedAt[id] = nil
        processDelegates[id] = nil
        sessions.removeAll { $0.id == id }
        if focusedSessionID == id {
            focusedSessionID = sessions.first?.id
        }
        Log.session.info("Closed session \(id.uuidString, privacy: .public)")
    }

    internal func closeAllSessions() {
        for session in sessions {
            recordActiveTime(for: session)
            session.terminalView.processDelegate = nil
            terminate(session: session)
        }
        usageTracking.stopAll()
        for tracker in gitTrackers.values {
            tracker.stop()
        }
        gitTrackers.removeAll()
        openedAt.removeAll()
        sessions.removeAll()
        processDelegates.removeAll()
        focusedSessionID = nil
    }

    internal func reload(id: TerminalSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else {
            return
        }
        let folder = session.folder
        let wasFocused = focusedSessionID == id
        closeSession(id: id)
        let new = makeSession(for: folder)
        if wasFocused {
            focusedSessionID = new.id
        }
    }

    internal func focus(id: TerminalSession.ID) {
        focusedSessionID = id
        if let session = sessions.first(where: { $0.id == id }), let window = session.terminalView.window {
            window.makeFirstResponder(session.terminalView)
        }
    }

    /// Creates a session. When `commandOverride` is provided it is injected into
    /// the shell instead of `folder.launchCommand` (e.g. to resume the most
    /// recent session via `claude --continue`).
    private func makeSession(for folder: FolderEntry, commandOverride: String? = nil) -> TerminalSession {
        let terminalView = launcher.makeTerminalView()
        let session = TerminalSession(folder: folder, terminalView: terminalView)

        let delegate = SessionProcessDelegate(sessionID: session.id) { [weak self] exitCode in
            self?.handleProcessTerminated(id: session.id, exitCode: exitCode)
        }
        processDelegates[session.id] = delegate
        terminalView.processDelegate = delegate

        sessions.append(session)
        if focusedSessionID == nil {
            focusedSessionID = session.id
        }

        openedAt[session.id] = Date()
        statsStore.recordPaneOpened(folderURL: folder.url)

        launcher.spawnShell(terminalView, folder.url, session.id)

        // Inject launch command after the shell has initialized.
        let command = commandOverride ?? folder.launchCommand
        DispatchQueue.main.asyncAfter(deadline: .now() + launcher.commandDelay) { [weak terminalView] in
            terminalView?.injectCommand(command)
        }

        verifyLaunchCommand(LaunchCommandResolver.baseCommand(of: command), for: session)
        startTrackers(for: session, command: command)

        Log.session.info("Spawned session for \(folder.url.path, privacy: .public) cmd=\(command, privacy: .public)")
        return session
    }

    private func startTrackers(for session: TerminalSession, command: String) {
        let folderURL = session.folder.url
        // Until the pane reports its own transcript, track the folder's latest
        // transcript under the launch command's alias (matched on the base
        // executable, so `claude --continue` still resolves to `claude`).
        usageTracking.start(session, fallbackConfigDir: aliasStore.alias(for: command)?.claudeConfigDir)

        // Track the folder's git branch for display in the pane chrome.
        let gitTracker = GitBranchTracker(folderURL: folderURL) { [weak session] branch in
            session?.gitBranch = branch
        }
        gitTrackers[session.id] = gitTracker
        gitTracker.start()
    }

    /// Flags the session when the launch command's executable can't be found,
    /// so the pane can explain why nothing is running instead of sitting on a
    /// bare `command not found` shell. Fast PATH probe first; on a miss,
    /// confirm with the interactive login shell off-main (rc files may add
    /// nvm/asdf paths or aliases the app doesn't inherit). Only a definite
    /// `.missing` warns; a timeout (`.unknown`) stays silent.
    private func verifyLaunchCommand(_ base: String, for session: TerminalSession) {
        guard !base.isEmpty, !launcher.isOnSearchPath(base) else {
            return
        }
        let shell = ShellResolver.userLoginShell()
        let loginShellAvailability = launcher.loginShellAvailability
        Task.detached(priority: .utility) {
            guard loginShellAvailability(base, shell) == .missing else {
                return
            }
            await MainActor.run { [weak session] in
                session?.errorMessage = "'\(base)' is not installed — the pane opened a plain shell. "
                    + "Install it or edit the project's launch command."
            }
            Log.session.error("Launch command not found: \(base, privacy: .public)")
        }
    }

    private func handleProcessTerminated(id: TerminalSession.ID, exitCode: Int32?) {
        guard let session = sessions.first(where: { $0.id == id }) else {
            return
        }
        session.isAlive = false
        session.lastExitCode = exitCode
        Log.session.info("Process terminated for session \(id.uuidString, privacy: .public), exit=\(exitCode ?? -1)")
    }

    private func recordActiveTime(for session: TerminalSession) {
        guard let start = openedAt[session.id] else {
            return
        }
        statsStore.recordActiveTime(folderURL: session.folder.url, seconds: Date().timeIntervalSince(start))
        openedAt[session.id] = nil
    }

    private func terminate(session: TerminalSession) {
        // SwiftTerm exposes terminate() on LocalProcess via the view.
        session.terminalView.process.terminate()
    }

    deinit {
        // Sessions are torn down explicitly via closeAllSessions(); nothing to release.
    }
}
