/// One open pane as persisted in `sessions.json`: the project it belongs to and,
/// when known, the Claude Code conversation it was running.
internal struct PaneSnapshot: Codable, Equatable {
    /// `FolderEntry.id` of the pane's project.
    internal let folderID: FolderEntry.ID
    /// Claude's `session_id` for the conversation last seen in this pane.
    internal let claudeSessionID: String?
}
