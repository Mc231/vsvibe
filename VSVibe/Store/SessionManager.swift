import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class SessionManager {
    private(set) var sessions: [TerminalSession] = []
    var focusedSessionID: TerminalSession.ID?

    @ObservationIgnored private var processDelegates: [TerminalSession.ID: SessionProcessDelegate] = [:]
    @ObservationIgnored private var usageTrackers: [TerminalSession.ID: UsageTracker] = [:]
    @ObservationIgnored private var gitTrackers: [TerminalSession.ID: GitBranchTracker] = [:]
    @ObservationIgnored private var openedAt: [TerminalSession.ID: Date] = [:]
    @ObservationIgnored private let statsStore: StatsStore

    @ObservationIgnored private let aliasStore: LaunchAliasStore

    init(statsStore: StatsStore, aliasStore: LaunchAliasStore) {
        self.aliasStore = aliasStore
        self.statsStore = statsStore
    }

    func ensureSession(for folder: FolderEntry, commandOverride: String? = nil) {
        if hasSession(forFolder: folder.id) { return }
        _ = makeSession(for: folder, commandOverride: commandOverride)
    }

    /// Always creates a new session for `folder` (allowing multiple panes per
    /// folder). The new session takes focus. Returns the freshly created session.
    @discardableResult
    func createSession(for folder: FolderEntry) -> TerminalSession {
        let session = makeSession(for: folder)
        focusedSessionID = session.id
        return session
    }

    func hasSession(forFolder folderID: FolderEntry.ID) -> Bool {
        sessions.contains { $0.folder.id == folderID }
    }

    func sessions(forFolder folderID: FolderEntry.ID) -> [TerminalSession] {
        sessions.filter { $0.folder.id == folderID }
    }

    func firstSession(forFolder folderID: FolderEntry.ID) -> TerminalSession? {
        sessions.first { $0.folder.id == folderID }
    }

    func closeAllSessions(forFolder folderID: FolderEntry.ID) {
        for session in sessions(forFolder: folderID) {
            closeSession(id: session.id)
        }
    }

    /// Creates a session. When `commandOverride` is provided it is injected into
    /// the shell instead of `folder.launchCommand` (e.g. to resume the most
    /// recent session via `claude --continue`).
    private func makeSession(for folder: FolderEntry, commandOverride: String? = nil) -> TerminalSession {
        let terminalView = makeTerminalView()
        let session = TerminalSession(folder: folder, terminalView: terminalView)

        let delegate = SessionProcessDelegate(sessionID: session.id) { [weak self] exitCode in
            self?.handleProcessTerminated(id: session.id, exitCode: exitCode)
        }
        processDelegates[session.id] = delegate
        terminalView.processDelegate = delegate

        sessions.append(session)
        if focusedSessionID == nil { focusedSessionID = session.id }

        openedAt[session.id] = Date()
        statsStore.recordPaneOpened(folderURL: folder.url)

        terminalView.spawnShell(at: folder.url)

        // Inject launch command after the shell has initialized.
        // Fixed delay is reliable enough; first PTY paint usually happens within ~150ms.
        let command = commandOverride ?? folder.launchCommand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak terminalView] in
            terminalView?.injectCommand(command)
        }

        verifyLaunchCommand(LaunchCommandResolver.baseCommand(of: command), for: session)

        // Start usage tracker for registered Claude-family aliases.
        // Match on the base executable so commands carrying flags (e.g.
        // `claude --continue`) still resolve to their alias.
        if let alias = aliasStore.alias(for: command),
           let configDir = alias.claudeConfigDir {
            let tracker = UsageTracker(folderURL: folder.url, configDir: configDir) { [weak session] usage in
                session?.usage = usage
            }
            usageTrackers[session.id] = tracker
            tracker.start()
        }

        // Track the folder's git branch for display in the pane chrome.
        let gitTracker = GitBranchTracker(folderURL: folder.url) { [weak session] branch in
            session?.gitBranch = branch
        }
        gitTrackers[session.id] = gitTracker
        gitTracker.start()

        Log.session.info("Spawned session for \(folder.url.path, privacy: .public) cmd=\(command, privacy: .public)")
        return session
    }

    func closeSession(id: TerminalSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        recordActiveTime(for: session)
        session.terminalView.processDelegate = nil
        terminate(session: session)
        usageTrackers[id]?.stop()
        usageTrackers[id] = nil
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

    func closeAllSessions() {
        for session in sessions {
            recordActiveTime(for: session)
            session.terminalView.processDelegate = nil
            terminate(session: session)
        }
        for tracker in usageTrackers.values { tracker.stop() }
        usageTrackers.removeAll()
        for tracker in gitTrackers.values { tracker.stop() }
        gitTrackers.removeAll()
        openedAt.removeAll()
        sessions.removeAll()
        processDelegates.removeAll()
        focusedSessionID = nil
    }

    func reload(id: TerminalSession.ID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let folder = session.folder
        let wasFocused = focusedSessionID == id
        closeSession(id: id)
        let new = makeSession(for: folder)
        if wasFocused { focusedSessionID = new.id }
    }

    func focus(id: TerminalSession.ID) {
        focusedSessionID = id
        if let session = sessions.first(where: { $0.id == id }), let window = session.terminalView.window {
            window.makeFirstResponder(session.terminalView)
        }
    }

    /// Flags the session when the launch command's executable can't be found,
    /// so the pane can explain why nothing is running instead of sitting on a
    /// bare `command not found` shell. Fast PATH probe first; on a miss,
    /// confirm with the login shell off-main (rc files may add nvm/asdf paths
    /// the app doesn't inherit).
    private func verifyLaunchCommand(_ base: String, for session: TerminalSession) {
        guard !base.isEmpty else { return }
        guard CommandLocator.resolveExecutable(base, searchPaths: EnvBuilder.searchPaths()) == nil else { return }
        let shell = ShellResolver.userLoginShell()
        Task.detached(priority: .utility) {
            let found = CommandLocator.loginShellCanFind(base, shell: shell)
            guard !found else { return }
            await MainActor.run { [weak session] in
                session?.errorMessage = "'\(base)' is not installed — the pane opened a plain shell. Install it or edit the project's launch command."
            }
            Log.session.error("Launch command not found: \(base, privacy: .public)")
        }
    }

    private func handleProcessTerminated(id: TerminalSession.ID, exitCode: Int32?) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.isAlive = false
        session.lastExitCode = exitCode
        Log.session.info("Process terminated for session \(id.uuidString, privacy: .public), exit=\(exitCode ?? -1)")
    }

    private func recordActiveTime(for session: TerminalSession) {
        guard let start = openedAt[session.id] else { return }
        statsStore.recordActiveTime(folderURL: session.folder.url, seconds: Date().timeIntervalSince(start))
        openedAt[session.id] = nil
    }

    private func terminate(session: TerminalSession) {
        // SwiftTerm exposes terminate() on LocalProcess via the view.
        session.terminalView.process.terminate()
    }

    private func makeTerminalView() -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

@MainActor
final class SessionProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    let sessionID: TerminalSession.ID
    let onTerminated: (Int32?) -> Void

    init(sessionID: TerminalSession.ID, onTerminated: @escaping (Int32?) -> Void) {
        self.sessionID = sessionID
        self.onTerminated = onTerminated
    }

    nonisolated func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
        // No-op; SwiftTerm handles TIOCSWINSZ internally.
    }

    nonisolated func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
        // No-op for now; could update PaneChromeView title.
    }

    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
        // No-op.
    }

    nonisolated func processTerminated(source _: TerminalView, exitCode: Int32?) {
        let code = exitCode
        Task { @MainActor [weak self] in
            self?.onTerminated(code)
        }
    }
}
