/// What a remote pane runs in its remote folder (see `SSHCommand.remoteScript`).
internal enum RemoteInvocation: Equatable {
    /// `exec <command>` in an interactive login shell (so remote aliases resolve).
    case command(String)
    /// `<command> --resume <id> || exec <command> --session-id <id>`: resumes the
    /// conversation, or starts it with that id when it was never started.
    case resumeOrStart(command: String, claudeSessionID: String)
    /// An interactive login shell.
    case shell
}
