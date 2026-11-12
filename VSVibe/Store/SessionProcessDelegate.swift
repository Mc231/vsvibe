import ObjectiveC
import SwiftTerm

/// Forwards SwiftTerm's process-exit callback to the main actor.
@MainActor
internal final class SessionProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    internal let sessionID: TerminalSession.ID
    internal let onTerminated: (Int32?) -> Void

    internal init(sessionID: TerminalSession.ID, onTerminated: @escaping (Int32?) -> Void) {
        self.sessionID = sessionID
        self.onTerminated = onTerminated
    }

    nonisolated internal func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {
        // No-op; SwiftTerm handles TIOCSWINSZ internally.
    }

    nonisolated internal func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {
        // No-op for now; could update PaneChromeView title.
    }

    nonisolated internal func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {
        // No-op.
    }

    nonisolated internal func processTerminated(source _: TerminalView, exitCode: Int32?) {
        let code = exitCode
        Task { @MainActor [weak self] in
            self?.onTerminated(code)
        }
    }

    deinit {
        // Holds only the callback; nothing to release.
    }
}
