import Foundation

internal enum LaunchCommandResolver {
    internal static let defaultCommand = "claude"

    /// Longest Claude session id accepted for `--resume` (ids are UUIDs).
    private static let maxClaudeSessionIDLength = 128
    private static let claudeSessionIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )
    /// Flags that pick a conversation and would conflict with `--resume <id>`.
    private static let conversationFlags: Set<String> = ["--continue", "-c"]
    /// Flags that may take the conversation id as their next argument.
    private static let resumeFlags: Set<String> = ["--resume", "-r"]

    /// Known launch aliases. For Claude-family aliases, the `claudeConfigDir`
    /// tells us where to install Stop/Notification hooks. opencode uses its
    /// own event system and is treated separately.
    internal static let aliases: [LaunchAlias] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            LaunchAlias(
                command: "claude",
                claudeConfigDir: home.appendingPathComponent(".claude", isDirectory: true)
            ),
            LaunchAlias(command: "opencode", claudeConfigDir: nil),
            LaunchAlias(command: "codex", claudeConfigDir: nil)
        ]
    }()

    internal static var knownAliases: [String] { aliases.map(\.command) }

    /// Aliases that use the Claude hooks system.
    internal static var hookCapableAliases: [LaunchAlias] {
        aliases.filter(\.supportsClaudeHooks)
    }

    internal static func alias(for command: String) -> LaunchAlias? {
        aliases.first { $0.command == command }
    }

    /// The executable token of a launch command, ignoring any trailing
    /// arguments (e.g. `baseCommand(of: "claude --continue") == "claude"`).
    /// Used for alias lookup when a command carries flags.
    internal static func baseCommand(of command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
    }

    /// Builds the command that resumes the most recent session by appending the
    /// `--continue` flag to `command`. Returns `command` unchanged when empty or
    /// when the flag is already present.
    internal static func continueCommand(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }
        let tokens = trimmed.split(separator: " ").map(String.init)
        if tokens.contains("--continue") || tokens.contains("-c") {
            return trimmed
        }
        return trimmed + " --continue"
    }

    /// Whether `id` is safe to type into a shell as a `--resume` argument:
    /// non-empty, bounded, and only letters, digits, `-` and `_`.
    internal static func isValidClaudeSessionID(_ id: String) -> Bool {
        !id.isEmpty
            && id.count <= maxClaudeSessionIDLength
            && id.unicodeScalars.allSatisfy { claudeSessionIDCharacters.contains($0) }
    }

    /// Builds the command that resumes one specific Claude conversation:
    /// `command` with any `--continue`/`-c`/`--resume [x]`/`-r [x]` removed and
    /// `--resume <claudeSessionID>` appended. Callers validate the id first
    /// (`isValidClaudeSessionID`).
    internal static func resumeCommand(for command: String, claudeSessionID: String) -> String {
        let tokens = command.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        var kept: [String] = []
        var index = tokens.startIndex
        while index < tokens.endIndex {
            let token = tokens[index]
            index += 1
            if resumeFlags.contains(token) {
                // Drop the flag's value too, unless the next token is another flag.
                if index < tokens.endIndex, !tokens[index].hasPrefix("-") {
                    index += 1
                }
            } else if !conversationFlags.contains(token), !token.hasPrefix("--resume=") {
                kept.append(token)
            }
        }
        return (kept + ["--resume", claudeSessionID]).joined(separator: " ")
    }

    /// All folders use the same default; custom commands are selected explicitly.
    internal static func defaultCommand(for _: URL) -> String {
        defaultCommand
    }
}
