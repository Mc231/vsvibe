import Foundation

/// Builds the line a remote pane types into its local shell:
///
///     ssh -t [-p PORT] -- 'DEST' '<remote script>'
///
/// The line is parsed twice: by the local shell, then (after ssh joins its
/// arguments) by the remote login shell, which runs the remote script. Both
/// levels use POSIX single quotes (`'` written as `'\''`), so nothing the user
/// typed is expanded locally. The remote script exports `VSVIBE_PANE_ID` and
/// runs the command in an interactive login shell (`-i -l -c`, like
/// `ShellProbe` locally) so remote aliases and rc-file PATHs work; the command
/// itself is the user's own command line and is deliberately not quoted into
/// one word. `exec` makes leaving the command end the ssh session.
///
/// Every field is validated first (`validationError(of:)`): the destination is
/// a strict character set and never starts with `-` (it also follows `--`),
/// the port is 1–65535 and no field may contain control characters (a newline
/// would submit the typed line early).
internal enum SSHCommand {
    /// The local executable remote panes run.
    internal static let executable = "ssh"

    private static let maxDestinationLength = 255
    private static let validPorts = 1...65_535
    private static let destinationCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@:%"
    )
    private static let homePrefix = "~/"
    private static let home = "~"

    /// The full line for `target`, or why it can't be built.
    internal static func line(
        for target: RemoteTarget,
        paneID: UUID,
        invocation: RemoteInvocation
    ) -> Result<String, RemoteTargetError> {
        if let error = validationError(of: target) ?? validationError(of: invocation) {
            return .failure(error)
        }
        var words = [executable, "-t"]
        if let port = target.port {
            words += ["-p", String(port)]
        }
        words += [
            "--",
            shellQuoted(target.destination),
            shellQuoted(remoteScript(for: target, paneID: paneID, invocation: invocation))
        ]
        return .success(words.joined(separator: " "))
    }

    /// What the remote login shell runs: change to the remote folder (exit if
    /// that fails), then exec the invocation with `VSVIBE_PANE_ID` exported.
    /// Callers validate `target` and `invocation` first.
    internal static func remoteScript(for target: RemoteTarget, paneID: UUID, invocation: RemoteInvocation) -> String {
        let changeDirectory = target.remotePath.isEmpty
            ? ""
            : "cd \(quotedRemotePath(target.remotePath)) || exit 1; "
        let shell = "exec env \(EnvBuilder.paneIDKey)=\(paneID.uuidString) \"$SHELL\""
        switch invocation {
        case .command(let command):
            return "\(shell) -i -l -c \(shellQuoted(changeDirectory + "exec " + command))"

        case let .resumeOrStart(command, claudeSessionID):
            let body = "\(command) --resume \(claudeSessionID) || exec \(command) --session-id \(claudeSessionID)"
            return "\(shell) -i -l -c \(shellQuoted(changeDirectory + body))"

        case .shell:
            return "\(changeDirectory)\(shell) -l"
        }
    }

    /// `text` as one POSIX shell word: single-quoted, `'` written as `'\''`.
    internal static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The remote folder as a shell word that still expands a leading `~` or
    /// `~/` on the remote host (the rest is quoted). A leading `-` gets `./`
    /// so `cd` can't read it as an option. `~user/…` is not expanded.
    internal static func quotedRemotePath(_ path: String) -> String {
        if path == home {
            return home
        }
        if path.hasPrefix(homePrefix) {
            let rest = String(path.dropFirst(homePrefix.count))
            return rest.isEmpty ? homePrefix : homePrefix + shellQuoted(rest)
        }
        return shellQuoted(path.hasPrefix("-") ? "./" + path : path)
    }

    /// The first problem with `target`, nil when it is safe to build.
    internal static func validationError(of target: RemoteTarget) -> RemoteTargetError? {
        if let error = validationError(ofDestination: target.destination) {
            return error
        }
        if let port = target.port, !validPorts.contains(port) {
            return .portOutOfRange
        }
        if hasControlCharacters(target.remotePath) {
            return .pathHasControlCharacters
        }
        return hasControlCharacters(target.command) ? .commandHasControlCharacters : nil
    }

    /// The first problem with an ssh destination, nil when it is safe.
    internal static func validationError(ofDestination destination: String) -> RemoteTargetError? {
        guard !destination.isEmpty else {
            return .destinationEmpty
        }
        guard destination.count <= maxDestinationLength else {
            return .destinationTooLong
        }
        guard !destination.hasPrefix("-") else {
            return .destinationStartsWithDash
        }
        guard destination.unicodeScalars.allSatisfy(destinationCharacters.contains) else {
            return .destinationHasInvalidCharacters
        }
        return destination.hasSuffix("@") ? .destinationEmpty : nil
    }

    private static func validationError(of invocation: RemoteInvocation) -> RemoteTargetError? {
        switch invocation {
        case .command(let command):
            return hasControlCharacters(command) ? .commandHasControlCharacters : nil

        case let .resumeOrStart(command, claudeSessionID):
            guard LaunchCommandResolver.isValidClaudeSessionID(claudeSessionID) else {
                return .invalidClaudeSessionID
            }
            return hasControlCharacters(command) ? .commandHasControlCharacters : nil

        case .shell:
            return nil
        }
    }

    private static func hasControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
