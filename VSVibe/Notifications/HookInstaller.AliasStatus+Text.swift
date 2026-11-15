import Foundation

/// Texts the hook setup window shows for one alias's hook status.
extension HookInstaller.AliasStatus {
    /// Which of the hook events are registered.
    internal var summary: String {
        if isInstalled {
            return HookInstaller.installedEvents.joined(separator: " + ") + " registered"
        }
        if registeredEvents.isEmpty {
            return "Not registered"
        }
        return "Partial: " + registeredEvents.joined(separator: ", ")
    }

    /// What to do when Claude has not used the alias's config dir yet (it was
    /// never run or never logged in), else nil.
    internal func setupHint(home: String = NSHomeDirectory()) -> String? {
        let path = alias.claudeConfigDir.map { HomePath.abbreviate($0.path, home: home) } ?? "(no config)"
        switch configDirState {
        case .missing:
            return "\(path) doesn't exist yet: run `\(alias.command)` once in a terminal and log in. "
                + "Installing the hooks creates it with a settings.json Claude Code will read."

        case .notSetUp:
            return "Claude Code hasn't used \(path) yet: run `\(alias.command)` once in a terminal and log in."

        case .ready:
            return nil
        }
    }
}
