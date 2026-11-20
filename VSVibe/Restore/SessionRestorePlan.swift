import Foundation

/// What to reopen on launch, derived from a `SessionSnapshot` and the current
/// projects by `make(snapshot:folders:lookups:)`.
internal struct SessionRestorePlan: Equatable {
    /// The outside world restore consults, injected so planning stays pure.
    internal struct Lookups {
        /// The alias a launch command runs (matched on its base command).
        internal let aliasForCommand: (String) -> LaunchAlias?
        /// The alias whose Claude config dir is this directory.
        internal let aliasForConfigDir: (URL) -> LaunchAlias?
        /// Whether a file exists at this absolute path.
        internal let fileExists: (String) -> Bool
    }

    /// Why a pane got its command.
    internal enum Resolution: Equatable {
        /// The project's plain launch command: no valid conversation id, or the
        /// command is a known alias without Claude hooks (e.g. `codex`).
        case launchCommand
        /// The transcript file no longer exists: the plain launch command,
        /// since `--resume` would fail.
        case transcriptMissing
        /// Resumed with the project's command; no transcript path was recorded
        /// (v1 snapshot or hook script older than v3).
        case resumedWithProjectCommand
        /// Resumed with the alias (`command`) whose config dir owns the transcript.
        case resumedWithOwningAlias(command: String)
        /// Resumed with the project's command (best effort): no alias uses the
        /// transcript's config dir (nil when none could be derived).
        case resumedWithUnknownConfigDir(URL?)
        /// A remote pane resuming its conversation (or starting it with the
        /// saved id): `command` is the remote command, see `RemoteLaunch`.
        case resumedRemote
    }

    /// One pane to reopen.
    internal struct Pane: Equatable {
        internal let folder: FolderEntry
        /// Command typed into the new shell: a launch command, with
        /// `--resume <id>` when the pane's Claude conversation can be resumed.
        /// For a remote project: the remote command (the pane itself resumes
        /// `claudeSessionID`, see `SessionManager.restoreSession`).
        internal let command: String
        /// Conversation the pane resumes (carried to the new pane so a later
        /// relaunch resumes it again); nil when the pane starts fresh.
        internal let claudeSessionID: String?
        /// Transcript of `claudeSessionID`, carried along with it.
        internal let transcriptPath: String?
        internal let resolution: Resolution

        /// The project's plain launch command, starting a new conversation.
        internal static func launching(_ folder: FolderEntry, resolution: Resolution) -> Self {
            Self(
                folder: folder,
                command: folder.primaryCommand,
                claudeSessionID: nil,
                transcriptPath: nil,
                resolution: resolution
            )
        }
    }

    /// A pane's known conversation, turned into a resuming `Pane`.
    private struct Conversation {
        let folder: FolderEntry
        let claudeSessionID: String
        let transcriptPath: String?

        /// The project's command with `--resume <id>`, or nil when that command
        /// cannot resume (empty, or a known alias without Claude hooks).
        func resumingProjectCommand(lookups: Lookups, resolution: Resolution) -> Pane? {
            let command = folder.launchCommand
            guard !LaunchCommandResolver.baseCommand(of: command).isEmpty,
                lookups.aliasForCommand(command)?.supportsClaudeHooks ?? true
            else {
                return nil
            }
            return pane(command: command, resolution: resolution)
        }

        /// Resumes with `owner`: the project's full command (its flags kept)
        /// when it runs that alias, otherwise the alias's bare command.
        func resuming(with owner: LaunchAlias) -> Pane {
            let projectCommand = folder.launchCommand
            let runsOwner = LaunchCommandResolver.baseCommand(of: projectCommand) == owner.command
            return pane(
                command: runsOwner ? projectCommand : owner.command,
                resolution: .resumedWithOwningAlias(command: owner.command)
            )
        }

        private func pane(command: String, resolution: Resolution) -> Pane {
            Pane(
                folder: folder,
                command: LaunchCommandResolver.resumeCommand(for: command, claudeSessionID: claudeSessionID),
                claudeSessionID: claudeSessionID,
                transcriptPath: transcriptPath,
                resolution: resolution
            )
        }
    }

    internal let panes: [Pane]
    /// Index into `panes` of the pane to focus.
    internal let focusedIndex: Int?

    /// Builds the plan. Panes whose project no longer exists are skipped
    /// (focus is dropped if it pointed at one); see `pane(for:saved:lookups:)`
    /// for how each pane's command is chosen.
    internal static func make(snapshot: SessionSnapshot, folders: [FolderEntry], lookups: Lookups) -> Self {
        var panes: [Pane] = []
        var focusedIndex: Int?
        for (index, saved) in snapshot.panes.enumerated() {
            guard let folder = folders.first(where: { $0.id == saved.folderID }) else {
                continue
            }
            if index == snapshot.focusedIndex {
                focusedIndex = panes.count
            }
            panes.append(pane(for: folder, saved: saved, lookups: lookups))
        }
        return Self(panes: panes, focusedIndex: focusedIndex)
    }

    /// Level 2 (resume) needs a valid conversation id. With a transcript path:
    /// a missing file means level 1; an alias owning its config dir resumes
    /// with that alias; otherwise the project's command resumes (best effort).
    /// Without one, the project's command resumes unless it is a known alias
    /// without Claude hooks.
    private static func pane(for folder: FolderEntry, saved: PaneSnapshot, lookups: Lookups) -> Pane {
        if let remote = folder.remote {
            return remotePane(for: folder, remote: remote, saved: saved)
        }
        let fresh = Pane.launching(folder, resolution: .launchCommand)
        guard let sessionID = saved.claudeSessionID, LaunchCommandResolver.isValidClaudeSessionID(sessionID) else {
            return fresh
        }
        guard let path = ClaudeTranscriptPath.validated(saved.transcriptPath, claudeSessionID: sessionID) else {
            let conversation = Conversation(folder: folder, claudeSessionID: sessionID, transcriptPath: nil)
            return conversation.resumingProjectCommand(lookups: lookups, resolution: .resumedWithProjectCommand)
                ?? fresh
        }
        guard lookups.fileExists(path) else {
            return Pane.launching(folder, resolution: .transcriptMissing)
        }
        let conversation = Conversation(folder: folder, claudeSessionID: sessionID, transcriptPath: path)
        let configDir = ClaudeTranscriptPath.configDir(ofTranscript: path)
        if let configDir, let owner = lookups.aliasForConfigDir(configDir) {
            return conversation.resuming(with: owner)
        }
        let unknownDir = Resolution.resumedWithUnknownConfigDir(configDir)
        return conversation.resumingProjectCommand(lookups: lookups, resolution: unknownDir) ?? fresh
    }

    /// A remote pane's command is the remote command; it resumes the saved
    /// conversation (`RemoteLaunch`: `--resume`, else start it with that id)
    /// when the project runs Claude and the id is valid. The transcript is on
    /// the remote host, so its path is neither checked nor carried.
    private static func remotePane(for folder: FolderEntry, remote: RemoteTarget, saved: PaneSnapshot) -> Pane {
        guard remote.launchesClaude,
            let sessionID = saved.claudeSessionID,
            LaunchCommandResolver.isValidClaudeSessionID(sessionID)
        else {
            return Pane.launching(folder, resolution: .launchCommand)
        }
        return Pane(
            folder: folder,
            command: remote.command,
            claudeSessionID: sessionID,
            transcriptPath: nil,
            resolution: .resumedRemote
        )
    }
}
