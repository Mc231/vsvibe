import Foundation

/// Runs one ssh call to completion (`SSHCommandRunner`; tests use a fake).
internal protocol RemoteShellRunning: Sendable {
    /// Runs ssh with `arguments` (see `RemoteSSH.commandArguments`), feeding
    /// `input` to its stdin (nothing when nil). Never blocks the caller.
    func run(arguments: [String], input: Data?) async -> RemoteCommandResult
}
