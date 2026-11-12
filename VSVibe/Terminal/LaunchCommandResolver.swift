import Foundation

struct LaunchAlias: Codable, Identifiable, Hashable {
    let command: String
    /// Claude-style settings.json config directory. `nil` if this alias does
    /// not use the Claude hooks system (e.g. opencode).
    let claudeConfigDir: URL?

    var id: String { command }
    var supportsClaudeHooks: Bool { claudeConfigDir != nil }
    var settingsURL: URL? { claudeConfigDir?.appendingPathComponent("settings.json") }
}

enum LaunchCommandResolver {
    static let defaultCommand = "claude"
    static let codex = "codex"

    /// Known launch aliases. For Claude-family aliases, the `claudeConfigDir`
    /// tells us where to install Stop/Notification hooks. opencode uses its
    /// own event system and is treated separately.
    static let aliases: [LaunchAlias] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            LaunchAlias(command: "claude",
                        claudeConfigDir: home.appendingPathComponent(".claude", isDirectory: true)),
            LaunchAlias(command: "opencode",
                        claudeConfigDir: nil),
            LaunchAlias(command: "codex", claudeConfigDir: nil)
        ]
    }()

    static var knownAliases: [String] { aliases.map(\.command) }

    static func alias(for command: String) -> LaunchAlias? {
        aliases.first { $0.command == command }
    }

    /// The executable token of a launch command, ignoring any trailing
    /// arguments (e.g. `baseCommand(of: "claude --continue") == "claude"`).
    /// Used for alias lookup when a command carries flags.
    static func baseCommand(of command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
    }

    /// Builds the command that resumes the most recent session by appending the
    /// `--continue` flag to `command`. Returns `command` unchanged when empty or
    /// when the flag is already present.
    static func continueCommand(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let tokens = trimmed.split(separator: " ").map(String.init)
        if tokens.contains("--continue") || tokens.contains("-c") { return trimmed }
        return trimmed + " --continue"
    }

    /// Aliases that use the Claude hooks system.
    static var hookCapableAliases: [LaunchAlias] {
        aliases.filter(\.supportsClaudeHooks)
    }

    /// All folders use the same default; custom commands are selected explicitly.
    static func defaultCommand(for url: URL) -> String {
        return defaultCommand
    }
}
