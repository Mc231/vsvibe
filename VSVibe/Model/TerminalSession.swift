import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let folder: FolderEntry
    @ObservationIgnored let terminalView: LocalProcessTerminalView
    var title: String
    var isAlive: Bool
    var lastExitCode: Int32?
    /// Human-readable problem with the pane (e.g. launch command not
    /// installed). Rendered as a dismissible banner above the terminal.
    var errorMessage: String?

    // Hook-driven activity state.
    var awaitingInput: Bool = false
    var unreadEventCount: Int = 0
    var lastEventAt: Date?
    var lastEventLabel: String?

    // Token usage from the latest Claude transcript for this folder.
    var usage: SessionUsage?

    // Current git branch for the folder, nil when not a git repo.
    var gitBranch: String?

    init(folder: FolderEntry, terminalView: LocalProcessTerminalView) {
        self.id = UUID()
        self.folder = folder
        self.terminalView = terminalView
        self.title = folder.displayName
        self.isAlive = true
    }
}
