import Foundation
import Observation

/// Routes Claude hook events (from `EventWatcher`) to the matching pane, the
/// stats store and user notifications.
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

    /// Applies one hook event: updates the matching pane (if any), records it
    /// in the stats and posts a notification.
    internal func handle(_ event: HookEvent) {
        lastEvent = event
        Log.app.info("Hook event: \(event.event.rawValue, privacy: .public) dir=\(event.projectDir, privacy: .public)")

        guard let session = matchSession(forProjectDir: event.projectDir) else {
            Log.app.info("No active session matches projectDir, posting generic notification")
            if !event.projectDir.isEmpty {
                statsStore.recordHookEvent(folderURL: URL(fileURLWithPath: event.projectDir), kind: event.event)
            }
            notifier.post(
                title: event.event.displayName,
                body: bestBody(for: event, folderName: URL(fileURLWithPath: event.projectDir).lastPathComponent),
                sessionID: nil
            )
            return
        }

        applyToSession(session, event: event)
        statsStore.recordHookEvent(folderURL: session.folder.url, kind: event.event)

        let folderName = folderStore.folders.first { $0.id == session.id }?.displayName
            ?? session.folder.displayName
        notifier.post(
            title: "\(folderName) — \(event.event.displayName)",
            body: bestBody(for: event, folderName: folderName),
            sessionID: session.id
        )
    }

    private func matchSession(forProjectDir projectDir: String) -> TerminalSession? {
        guard !projectDir.isEmpty else {
            return nil
        }
        let target = URL(fileURLWithPath: projectDir).standardizedFileURL.resolvingSymlinksInPath().path
        return sessionManager.sessions.first { session in
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

        case .unknown:
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

        case .unknown:
            return "Event in \(folderName)."
        }
    }

    deinit {
        // The watcher is stopped explicitly via stop(); nothing else to release.
    }
}
