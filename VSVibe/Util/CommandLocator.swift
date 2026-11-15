import Foundation

/// Checks whether a launch command's executable exists. The fast check walks an
/// explicit PATH list (the same one `EnvBuilder` hands the spawned shell); the
/// slow check asks the user's interactive login shell, which also sees
/// rc-managed paths (nvm, asdf, …) and aliases the app itself doesn't inherit.
internal enum CommandLocator {
    /// Absolute path of `command` resolved against `searchPaths`, or nil when
    /// not found. `command` must be a bare executable token (no arguments) —
    /// strip flags with `LaunchCommandResolver.baseCommand(of:)` first.
    internal static func resolveExecutable(
        _ command: String,
        searchPaths: [String],
        fileManager: FileManager = .default
    ) -> String? {
        guard !command.isEmpty else {
            return nil
        }
        if command.contains("/") {
            let path = expandingTilde(in: command)
            return fileManager.isExecutableFile(atPath: path) ? path : nil
        }
        for dir in searchPaths where !dir.isEmpty {
            let candidate = dir.hasSuffix("/") ? dir + command : dir + "/" + command
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Authoritative check via the user's interactive login shell
    /// (`<shell> -i -l -c "command -v '<command>'"`), which also sees aliases
    /// and functions from `~/.zshrc` / `~/.bashrc`. Runs the shell's rc files,
    /// so it is slow and bounded by `timeout`: only call off the main thread,
    /// and only after `resolveExecutable` came up empty.
    ///
    /// `.unknown` (a timeout, a shell that can't start, or a name that is not a
    /// plain `ShellCommandName`, which is never put into a script) means
    /// "don't warn".
    internal static func loginShellAvailability(
        _ command: String,
        shell: String,
        timeout: TimeInterval = ShellProbe.defaultTimeout
    ) -> CommandAvailability {
        guard let quoted = ShellCommandName.quoted(command) else {
            return .unknown
        }
        let script = "command -v \(quoted) >/dev/null 2>&1"
        let arguments = ShellProbe.interactiveLoginArguments + [script]
        switch ShellProbe.run(shell: shell, arguments: arguments, timeout: timeout) {
        case .exited(let status, _):
            return status == 0 ? .found : .missing

        case .timedOut, .failedToLaunch:
            return .unknown
        }
    }

    /// Swift-native equivalent of `NSString.expandingTildeInPath` for the
    /// current user (`~` and `~/…`); other paths are returned unchanged.
    private static func expandingTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return NSHomeDirectory() + path.dropFirst()
    }
}
