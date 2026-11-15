import Foundation

/// A launch command that is not a registered VSVibe alias but may be a shell
/// alias for a Claude account (`CLAUDE_CONFIG_DIR=… claude`), so VSVibe can
/// offer to register it (hooks, usage tracking, restore).
internal struct UnregisteredClaudeCommand: Equatable, Identifiable {
    /// Launch commands that are known not to be Claude Code: other agents'
    /// CLIs, shells and everyday tools. They are never probed or listed.
    internal static let nonClaudeTools: Set<String> = [
        "aider", "bash", "codex", "csh", "dash", "emacs", "fish", "gemini", "git", "htop", "ksh", "lazygit",
        "ls", "make", "nano", "node", "npm", "npx", "nu", "nvim", "opencode", "python", "python3", "screen",
        "sh", "ssh", "tcsh", "tmux", "top", "vi", "vim", "zsh"
    ]

    /// The base command (an alias name).
    internal let command: String
    /// The `CLAUDE_CONFIG_DIR` its shell definition sets, when detected.
    internal let configDir: URL?

    internal var id: String { command }

    /// The base command of `launchCommand` when it is worth asking the shell
    /// about: a valid command name that is neither a registered alias (the
    /// built-in `claude` included) nor a known non-Claude tool.
    internal static func candidate(forLaunchCommand launchCommand: String, aliases: [LaunchAlias]) -> String? {
        let base = LaunchCommandResolver.baseCommand(of: launchCommand)
        guard ShellCommandName.isValid(base),
            !nonClaudeTools.contains(base),
            !aliases.contains(where: { $0.command == base })
        else {
            return nil
        }
        return base
    }

    /// Asks the user's interactive login shell (off the main thread) which
    /// Claude config dir `command` uses.
    internal static func detect(
        _ command: String,
        resolver: ShellAliasResolver = .live,
        shell: String = ShellResolver.userLoginShell()
    ) async -> Self {
        let configDir = await Task.detached(priority: .utility) {
            resolver.claudeConfigDir(forCommand: command, shell: shell)
        }
        .value
        return Self(command: command, configDir: configDir)
    }

    /// Distinct candidates of `launchCommands`, in first-seen order.
    internal static func candidates(forLaunchCommands launchCommands: [String], aliases: [LaunchAlias]) -> [String] {
        var seen: Set<String> = []
        return launchCommands.compactMap { command in
            guard let base = candidate(forLaunchCommand: command, aliases: aliases), seen.insert(base).inserted else {
                return nil
            }
            return base
        }
    }

    /// `configDir` with the home directory shown as `~`.
    internal func displayConfigDir(home: String = NSHomeDirectory()) -> String? {
        configDir.map { HomePath.abbreviate($0.path, home: home) }
    }

    /// Markdown notice for the project editor, or nil without a config dir.
    internal func notice(home: String = NSHomeDirectory()) -> String? {
        guard let path = displayConfigDir(home: home) else {
            return nil
        }
        return "`\(command)` uses Claude account `\(path)`, not registered in VSVibe."
    }
}
