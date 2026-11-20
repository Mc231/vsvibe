import Foundation

/// Read-only views of the open panes.
internal extension SessionManager {
    /// The open panes (in order) and focus, as persisted for restore on launch.
    var snapshot: SessionSnapshot {
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

    func hasSession(forFolder folderID: FolderEntry.ID) -> Bool {
        sessions.contains { $0.folder.id == folderID }
    }

    func sessions(forFolder folderID: FolderEntry.ID) -> [TerminalSession] {
        sessions.filter { $0.folder.id == folderID }
    }

    func firstSession(forFolder folderID: FolderEntry.ID) -> TerminalSession? {
        sessions.first { $0.folder.id == folderID }
    }
}
