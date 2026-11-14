import Foundation

/// What to reopen on launch, derived from a `SessionSnapshot` and the current
/// projects by `make(snapshot:folders:aliasLookup:)`.
internal struct SessionRestorePlan: Equatable {
    /// One pane to reopen.
    internal struct Pane: Equatable {
        internal let folder: FolderEntry
        /// Command typed into the new shell: the project's launch command, with
        /// `--resume <id>` when the pane's Claude conversation is known.
        internal let command: String
        /// Conversation the pane resumes (carried to the new pane so a later
        /// relaunch resumes it again); nil when the pane starts fresh.
        internal let claudeSessionID: String?
    }

    internal let panes: [Pane]
    /// Index into `panes` of the pane to focus.
    internal let focusedIndex: Int?

    /// Builds the plan. Panes whose project no longer exists are skipped
    /// (focus is dropped if it pointed at one). A pane resumes its Claude
    /// conversation (level 2) when the id is valid and its launch command is
    /// not a known non-Claude alias; otherwise it gets the plain launch command
    /// (level 1).
    internal static func make(
        snapshot: SessionSnapshot,
        folders: [FolderEntry],
        aliasLookup: (String) -> LaunchAlias?
    ) -> Self {
        var panes: [Pane] = []
        var focusedIndex: Int?
        for (index, saved) in snapshot.panes.enumerated() {
            guard let folder = folders.first(where: { $0.id == saved.folderID }) else {
                continue
            }
            if index == snapshot.focusedIndex {
                focusedIndex = panes.count
            }
            panes.append(pane(for: folder, claudeSessionID: saved.claudeSessionID, aliasLookup: aliasLookup))
        }
        return Self(panes: panes, focusedIndex: focusedIndex)
    }

    private static func pane(
        for folder: FolderEntry,
        claudeSessionID: String?,
        aliasLookup: (String) -> LaunchAlias?
    ) -> Pane {
        let command = folder.launchCommand
        guard let claudeSessionID,
            LaunchCommandResolver.isValidClaudeSessionID(claudeSessionID),
            canResume(command: command, alias: aliasLookup(command))
        else {
            return Pane(folder: folder, command: command, claudeSessionID: nil)
        }
        return Pane(
            folder: folder,
            command: LaunchCommandResolver.resumeCommand(for: command, claudeSessionID: claudeSessionID),
            claudeSessionID: claudeSessionID
        )
    }

    /// `--resume` is only appended to a non-empty command that is not a known
    /// alias without Claude hooks (e.g. `codex`); unknown commands may wrap Claude.
    private static func canResume(command: String, alias: LaunchAlias?) -> Bool {
        guard !LaunchCommandResolver.baseCommand(of: command).isEmpty else {
            return false
        }
        return alias?.supportsClaudeHooks ?? true
    }
}
