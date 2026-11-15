/// One open pane as persisted in `sessions.json`: the project it belongs to and,
/// when known, the Claude Code conversation it was running.
internal struct PaneSnapshot: Codable, Equatable {
    /// `FolderEntry.id` of the pane's project.
    internal let folderID: FolderEntry.ID
    /// Claude's `session_id` for the conversation last seen in this pane.
    internal let claudeSessionID: String?
    /// Claude's `transcript_path` for that conversation (v2): tells restore
    /// which config dir, and so which alias, owns it. Absent in v1 files.
    internal let transcriptPath: String?

    internal init(folderID: FolderEntry.ID, claudeSessionID: String?, transcriptPath: String? = nil) {
        self.folderID = folderID
        self.claudeSessionID = claudeSessionID
        self.transcriptPath = transcriptPath
    }
}
