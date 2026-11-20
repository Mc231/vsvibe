import Foundation

/// Manages installing/uninstalling the VSVibe Claude hook script and entries in
/// each Claude alias's `settings.json` (each alias may use its own
/// `CLAUDE_CONFIG_DIR`).
///
/// The script location defaults to `hookScriptURL` and can be overridden per
/// call (tests point it at a temporary directory).
@MainActor
internal enum HookInstaller {
    internal struct AliasStatus: Equatable, Identifiable {
        internal let alias: LaunchAlias
        internal let registeredEvents: [String]
        /// Whether Claude has used the alias's config dir yet (see
        /// `ClaudeConfigDirState`); not part of `isInstalled`.
        internal var configDirState: ClaudeConfigDirState = .ready

        internal var id: String { alias.id }
        /// Every event the current installer registers is present.
        internal var isInstalled: Bool {
            HookInstaller.installedEvents.allSatisfy(registeredEvents.contains)
        }
    }

    internal struct Status: Equatable {
        internal let scriptInstalled: Bool
        /// The installed script differs from the one this build writes.
        internal let scriptOutdated: Bool
        internal let aliases: [AliasStatus]

        internal var isFullyInstalled: Bool {
            scriptInstalled && !scriptOutdated && !aliases.isEmpty && aliases.allSatisfy(\.isInstalled)
        }

        internal var isPartiallyInstalled: Bool {
            scriptInstalled && aliases.contains(where: \.isInstalled) && !isFullyInstalled
        }

        /// Installed by an older VSVibe: the script is outdated or an alias has
        /// some, but not all, of the events the current version registers.
        internal var needsUpdate: Bool {
            scriptInstalled
                && (scriptOutdated || aliases.contains { !$0.isInstalled && !$0.registeredEvents.isEmpty })
        }

        /// Title of the install button in the hook setup UI.
        internal var installActionTitle: String {
            if needsUpdate {
                return "Update Hooks"
            }
            return isPartiallyInstalled ? "Reinstall Hooks" : "Install Hooks"
        }

        internal init(scriptInstalled: Bool, aliases: [AliasStatus], scriptOutdated: Bool = false) {
            self.scriptInstalled = scriptInstalled
            self.scriptOutdated = scriptOutdated
            self.aliases = aliases
        }
    }

    nonisolated internal static let appDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".vsvibe", isDirectory: true)
    }()

    nonisolated internal static let hookScriptURL: URL = appDir.appendingPathComponent("hooks/claude-notify.sh")
    nonisolated internal static let eventsFileURL: URL = appDir.appendingPathComponent("events.jsonl")
    nonisolated internal static let hookCommandIdentifier = "vsvibe:claude-notify"

    /// Events the installer registers. `SessionStart` tells VSVibe each pane's
    /// Claude session id before the first turn finishes (and after `/clear`).
    nonisolated internal static let installedEvents = ["SessionStart", "Stop", "Notification"]
    private static let scriptPermissions: Int16 = 0o755

    // MARK: - Status

    internal static var isScriptInstalled: Bool {
        isScriptInstalled(at: hookScriptURL)
    }

    internal static func isScriptInstalled(at scriptURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: scriptURL.path)
    }

    /// Whether the script at `scriptURL` is exactly the one this build writes.
    internal static func isScriptCurrent(at scriptURL: URL) -> Bool {
        (try? String(contentsOf: scriptURL, encoding: .utf8)) == HookScript.contents
    }

    internal static func currentStatus(aliases: [LaunchAlias], scriptURL: URL = hookScriptURL) -> Status {
        let scriptOK = isScriptInstalled(at: scriptURL)
        let aliasStatuses: [AliasStatus] = aliases.compactMap { alias in
            guard let settingsURL = alias.settingsURL else {
                return nil
            }
            let events = (try? readSettings(at: settingsURL))
                .map { HookSettings.registeredEvents(inSettings: $0, scriptPath: hookScriptURL.path) } ?? []
            let dirState = alias.claudeConfigDir.map { ClaudeConfigDirState.of($0) } ?? .missing
            return AliasStatus(alias: alias, registeredEvents: events, configDirState: dirState)
        }
        return Status(
            scriptInstalled: scriptOK,
            aliases: aliasStatuses,
            scriptOutdated: scriptOK && !isScriptCurrent(at: scriptURL)
        )
    }

    // MARK: - Install / Uninstall

    internal static func writeScript(to scriptURL: URL = hookScriptURL) throws {
        let fileManager = FileManager.default
        let dir = scriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try HookScript.contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: scriptPermissions], ofItemAtPath: scriptURL.path)
    }

    internal static func install(aliases: [LaunchAlias], scriptURL: URL = hookScriptURL) throws {
        try writeScript(to: scriptURL)
        for alias in aliases.filter(\.supportsClaudeHooks) {
            try installInto(alias: alias)
        }
    }

    /// Registers the hooks in the alias's `settings.json`. A missing config
    /// dir is created along with the file: Claude Code reads
    /// `$CLAUDE_CONFIG_DIR/settings.json`, so the hooks are active from the
    /// alias's first run (the status still reports it as not set up until
    /// Claude writes there).
    internal static func installInto(alias: LaunchAlias) throws {
        guard let settingsURL = alias.settingsURL else {
            return
        }
        try mutateSettings(at: settingsURL) { json in
            json = HookSettings.installing(
                into: json,
                scriptPath: hookScriptURL.path,
                scriptCommand: hookScriptURL.path
            )
        }
    }

    internal static func uninstall(aliases: [LaunchAlias]) throws {
        for alias in aliases.filter(\.supportsClaudeHooks) {
            try uninstallFrom(alias: alias)
        }
    }

    internal static func uninstallFrom(alias: LaunchAlias) throws {
        guard let settingsURL = alias.settingsURL else {
            return
        }
        try mutateSettings(at: settingsURL) { json in
            json = HookSettings.uninstalling(from: json, scriptPath: hookScriptURL.path)
        }
    }

    internal static func unsupportedAliases(in aliases: [LaunchAlias]) -> [LaunchAlias] {
        aliases.filter { !$0.supportsClaudeHooks }
    }

    // MARK: - Private helpers

    private static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        return try HookSettings.object(from: Data(contentsOf: url))
    }

    private static func mutateSettings(at url: URL, _ mutate: (inout [String: Any]) -> Void) throws {
        let fileManager = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        var json: [String: Any] = (try? readSettings(at: url)) ?? [:]

        if fileManager.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("vsvibe.bak")
            _ = try? fileManager.removeItem(at: backup)
            try? fileManager.copyItem(at: url, to: backup)
        }

        mutate(&json)

        try HookSettings.data(of: json).write(to: url, options: [.atomic])
    }
}
