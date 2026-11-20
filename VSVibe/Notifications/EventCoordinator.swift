import Foundation
import Observation

/// Routes Claude hook events to the matching pane, the stats store and user
/// notifications: events of the local events file (`EventWatcher`) to local
/// panes, events streamed from a remote host (`RemotePaneMonitor`) to the
/// remote pane named by their `paneId` only.
@MainActor
@Observable
internal final class EventCoordinator {
    internal var lastEvent: HookEvent?

    private let folderStore: FolderStore
    private let sessionManager: SessionManager
    private let statsStore: StatsStore
    @ObservationIgnored private let notifier: any HookEventNotifying
    @ObservationIgnored private let eventsURL: URL
    @ObservationIgnored private var watcher: EventWatcher?

    /// Whether the events file is currently being watched.
    internal var isWatching: Bool { watcher?.isRunning ?? false }

    internal init(
        folderStore: FolderStore,
        sessionManager: SessionManager,
        statsStore: StatsStore,
        notifier: (any HookEventNotifying)? = nil,
        eventsURL: URL = HookInstaller.eventsFileURL
    ) {
        self.folderStore = folderStore
        self.sessionManager = sessionManager
        self.statsStore = statsStore
        self.notifier = notifier ?? AppNotifications.shared
        self.eventsURL = eventsURL
    }

    internal func start() {
        notifier.configure { [weak self] id in
            self?.sessionManager.focus(id: id)
        }
        let eventWatcher = EventWatcher(url: eventsURL) { [weak self] event in
            self?.handle(event)
        }
        watcher = eventWatcher
        eventWatcher.start()
    }

    internal func stop() {
        watcher?.stop()
        watcher = nil
    }

    internal func clearUnread(for sessionID: TerminalSession.ID) {
        if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
            session.unreadEventCount = 0
            session.awaitingInput = false
        }
    }

    /// Applies one event of the local events file: updates the matching
    /// local pane (if any), records it in the stats and posts a notification.
    /// `SessionStart` only records the pane's Claude session id. Events naming
    /// a remote pane are left to its host's stream (`handleRemote`).
    internal func handle(_ event: HookEvent) {
        log(event)
        let paneMatch = event.paneID.flatMap(openSession(withID:))
        if paneMatch?.folder.isRemote == true {
            return
        }
        guard let session = paneMatch ?? matchSession(forProjectDir: event.projectDir) else {
            if event.event != .sessionStart {
                handleUnmatched(event)
            }
            return
        }
        apply(event, to: session)
    }

    /// Applies one event streamed from a remote host. It only ever reaches the
    /// open remote pane its `paneId` names; anything else (another machine's
    /// pane, a terminal outside VSVibe) is dropped.
    internal func handleRemote(_ event: HookEvent) {
        log(event)
        guard let session = event.paneID.flatMap(openSession(withID:)), session.folder.isRemote else {
            Log.app.info("Remote hook event for no open remote pane, ignored")
            return
        }
        apply(event, to: session)
    }

    private func log(_ event: HookEvent) {
        lastEvent = event
        Log.app.info("Hook event: \(event.event.rawValue, privacy: .public) dir=\(event.projectDir, privacy: .public)")
    }

    /// Records the conversation, then (except for `SessionStart`) updates the
    /// pane, the stats and posts a notification.
    private func apply(_ event: HookEvent, to session: TerminalSession) {
        recordClaudeSessionID(of: event, in: session)
        guard event.event != .sessionStart else {
            return
        }
        applyToSession(session, event: event)
        statsStore.recordHookEvent(folderURL: session.folder.url, kind: event.event)

        // The project's current name (it may have been renamed since the pane opened).
        let folderName = folderStore.folders.first { $0.id == session.folder.id }?.displayName
            ?? session.folder.displayName
        notifier.post(
            title: "\(folderName) — \(event.event.displayName)",
            body: bestBody(for: event, folderName: folderName),
            sessionID: session.id
        )
    }

    private func handleUnmatched(_ event: HookEvent) {
        Log.app.info("No active session matches the event, posting generic notification")
        if !event.projectDir.isEmpty {
            statsStore.recordHookEvent(folderURL: URL(fileURLWithPath: event.projectDir), kind: event.event)
        }
        notifier.post(
            title: event.event.displayName,
            body: bestBody(for: event, folderName: URL(fileURLWithPath: event.projectDir).lastPathComponent),
            sessionID: nil
        )
    }

    private func openSession(withID id: TerminalSession.ID) -> TerminalSession? {
        sessionManager.sessions.first { $0.id == id }
    }

    /// Keeps the latest Claude session id of a pane, with its transcript path
    /// when the event carries a valid one for that id (else the path is
    /// cleared: it would belong to an older conversation). Only events
    /// carrying the pane's own id count: a folder match is ambiguous with
    /// several panes.
    private func recordClaudeSessionID(of event: HookEvent, in session: TerminalSession) {
        guard event.paneID == session.id,
            let claudeSessionID = event.claudeSessionID,
            LaunchCommandResolver.isValidClaudeSessionID(claudeSessionID)
        else {
            return
        }
        let transcriptPath = ClaudeTranscriptPath.validated(event.transcriptPath, claudeSessionID: claudeSessionID)
        sessionManager.recordClaudeConversation(claudeSessionID, transcriptPath: transcriptPath, in: session)
    }

    /// The first local pane whose folder is the event's project dir (events
    /// from old hook scripts or from terminals outside VSVibe).
    private func matchSession(forProjectDir projectDir: String) -> TerminalSession? {
        guard !projectDir.isEmpty else {
            return nil
        }
        let target = URL(fileURLWithPath: projectDir).standardizedFileURL.resolvingSymlinksInPath().path
        return sessionManager.sessions.first { session in
            guard !session.folder.isRemote else {
                return false
            }
            let sessionPath = session.folder.url.standardizedFileURL.resolvingSymlinksInPath().path
            return sessionPath == target
        }
    }

    private func applyToSession(_ session: TerminalSession, event: HookEvent) {
        session.lastEventAt = Date(timeIntervalSince1970: event.timestamp)
        switch event.event {
        case .notification:
            session.awaitingInput = true
            session.unreadEventCount += 1
            session.lastEventLabel = event.message ?? "Needs input"

        case .stop, .subagentStop:
            session.awaitingInput = false
            session.unreadEventCount += 1
            session.lastEventLabel = "Finished"

        case .sessionStart, .unknown:
            break
        }
    }

    private func bestBody(for event: HookEvent, folderName: String) -> String {
        if let message = event.message, !message.isEmpty {
            return message
        }
        switch event.event {
        case .notification:
            return "Claude is waiting for input in \(folderName)."

        case .stop:
            return "Claude finished a response in \(folderName)."

        case .subagentStop:
            return "Subagent finished in \(folderName)."

        case .sessionStart, .unknown:
            return "Event in \(folderName)."
        }
    }

    deinit {
        // The watcher is stopped explicitly via stop(); nothing else to release.
    }
}
