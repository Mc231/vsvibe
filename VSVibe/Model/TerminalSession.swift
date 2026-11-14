import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
internal final class TerminalSession: Identifiable {
    internal let id: UUID
    internal let folder: FolderEntry
    @ObservationIgnored internal let terminalView: LocalProcessTerminalView
    internal var title: String
    internal var isAlive: Bool
    internal var lastExitCode: Int32?
    /// Human-readable problem with the pane (e.g. launch command not
    /// installed). Rendered as a dismissible banner above the terminal.
    internal var errorMessage: String?

    // Hook-driven activity state.
    internal var awaitingInput = false
    internal var unreadEventCount = 0
    internal var lastEventAt: Date?
    internal var lastEventLabel: String?

    /// Claude's `session_id` for the conversation running in this pane, from
    /// hook events carrying this pane's id (the latest wins, e.g. after
    /// `/clear`), or carried over when the pane was restored. Persisted so the
    /// next launch can `--resume` it.
    internal var claudeSessionID: String?

    // Token usage from the latest Claude transcript for this folder.
    internal var usage: SessionUsage?

    // Current git branch for the folder, nil when not a git repo.
    internal var gitBranch: String?

    internal init(folder: FolderEntry, terminalView: LocalProcessTerminalView) {
        self.id = UUID()
        self.folder = folder
        self.terminalView = terminalView
        self.title = folder.displayName
        self.isAlive = true
    }

    deinit {
        // Nothing to release: the terminal view is owned and torn down by SessionManager.
    }
}
