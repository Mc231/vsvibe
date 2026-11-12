import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class EventCoordinator {
    private let folderStore: FolderStore
    private let sessionManager: SessionManager
    private let statsStore: StatsStore
    @ObservationIgnored private var watcher: EventWatcher?

    var lastEvent: HookEvent?

    init(folderStore: FolderStore, sessionManager: SessionManager, statsStore: StatsStore) {
        self.folderStore = folderStore
        self.sessionManager = sessionManager
        self.statsStore = statsStore
    }

    func start() {
        AppNotifications.shared.configure { [weak self] id in
            self?.sessionManager.focus(id: id)
        }
        let w = EventWatcher { [weak self] event in
            self?.handle(event)
        }
        watcher = w
        w.start()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func handle(_ event: HookEvent) {
        lastEvent = event
        Log.app.info("Hook event: \(event.event.rawValue, privacy: .public) dir=\(event.projectDir, privacy: .public)")

        guard let session = matchSession(forProjectDir: event.projectDir) else {
            Log.app.info("No active session matches projectDir, posting generic notification")
            if !event.projectDir.isEmpty {
                statsStore.recordHookEvent(folderURL: URL(fileURLWithPath: event.projectDir), kind: event.event)
            }
            AppNotifications.shared.post(
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
        AppNotifications.shared.post(
            title: "\(folderName) — \(event.event.displayName)",
            body: bestBody(for: event, folderName: folderName),
            sessionID: session.id
        )
    }

    private func matchSession(forProjectDir projectDir: String) -> TerminalSession? {
        guard !projectDir.isEmpty else { return nil }
        let target = URL(fileURLWithPath: projectDir).standardizedFileURL.resolvingSymlinksInPath().path
        return sessionManager.sessions.first { session in
            let sessionPath = session.folder.url.standardizedFileURL.resolvingSymlinksInPath().path
            return sessionPath == target
        }
    }

    private func applyToSession(_ session: TerminalSession, event: HookEvent) {
        session.lastEventAt = Date(timeIntervalSince1970: event.ts)
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
        if let msg = event.message, !msg.isEmpty {
            return msg
        }
        switch event.event {
        case .notification: return "Claude is waiting for input in \(folderName)."
        case .stop: return "Claude finished a response in \(folderName)."
        case .subagentStop: return "Subagent finished in \(folderName)."
        case .unknown: return "Event in \(folderName)."
        }
    }

    func clearUnread(for sessionID: TerminalSession.ID) {
        if let session = sessionManager.sessions.first(where: { $0.id == sessionID }) {
            session.unreadEventCount = 0
            session.awaitingInput = false
        }
    }
}
