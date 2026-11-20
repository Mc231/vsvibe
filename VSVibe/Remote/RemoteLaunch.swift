import Foundation

/// Decides what a new remote pane runs and which Claude conversation it owns.
///
/// Remote panes have no Claude hooks yet (no `SessionStart` reporting the
/// conversation id), so for a Claude command VSVibe chooses the id itself:
/// a fresh pane runs `<command> --session-id <new id>` and records that id at
/// once; a restored pane resumes its recorded id, falling back to starting it
/// (`RemoteInvocation.resumeOrStart`) when the conversation never began.
internal enum RemoteLaunch {
    /// The pane's invocation and the conversation id to record for it (nil:
    /// none known, e.g. a plain shell or a command that picks its own
    /// conversation with `--continue`).
    internal struct Plan: Equatable {
        internal let invocation: RemoteInvocation
        internal let claudeSessionID: String?
    }

    /// - Parameters:
    ///   - newClaudeSessionID: The id a fresh Claude conversation starts with.
    ///   - commandOverride: Runs instead of the target's command (e.g. its
    ///     `--continue` variant, or the command a restore carried).
    ///   - resumeClaudeSessionID: The conversation a restored pane resumes.
    internal static func plan(
        for target: RemoteTarget,
        newClaudeSessionID: UUID,
        commandOverride: String? = nil,
        resumeClaudeSessionID: String? = nil
    ) -> Plan {
        let command = (commandOverride ?? target.command).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return Plan(invocation: .shell, claudeSessionID: nil)
        }
        let plain = Plan(invocation: .command(command), claudeSessionID: nil)
        guard target.runsClaude else {
            return plain
        }
        if let id = resumeClaudeSessionID, LaunchCommandResolver.isValidClaudeSessionID(id) {
            let base = LaunchCommandResolver.withoutConversationFlags(command)
            guard !base.isEmpty else {
                return plain
            }
            return Plan(invocation: .resumeOrStart(command: base, claudeSessionID: id), claudeSessionID: id)
        }
        guard !LaunchCommandResolver.hasConversationFlag(command) else {
            return plain
        }
        let id = newClaudeSessionID.uuidString.lowercased()
        return Plan(invocation: .command("\(command) --session-id \(id)"), claudeSessionID: id)
    }
}
