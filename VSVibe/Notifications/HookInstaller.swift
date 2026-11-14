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
    /// Events the installer recognises (and cleans up) as its own.
    private static let managedEvents = ["SessionStart", "Stop", "Notification", "SubagentStop"]
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
                .flatMap { ($0["hooks"] as? [String: Any]).map(registeredEvents(in:)) } ?? []
            return AliasStatus(alias: alias, registeredEvents: events)
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

    internal static func installInto(alias: LaunchAlias) throws {
        guard let settingsURL = alias.settingsURL else {
            return
        }
        try mutateSettings(at: settingsURL) { json in
            var hooks = (json["hooks"] as? [String: Any]) ?? [:]
            for event in installedEvents {
                var entries = (hooks[event] as? [[String: Any]]) ?? []
                entries.removeAll { ownsEntry($0) }
                entries.append(makeEntry(forEvent: event))
                hooks[event] = entries
            }
            json["hooks"] = hooks
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
            guard var hooks = json["hooks"] as? [String: Any] else {
                return
            }
            for event in managedEvents {
                guard var entries = hooks[event] as? [[String: Any]] else {
                    continue
                }
                entries.removeAll { ownsEntry($0) }
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
            if hooks.isEmpty {
                json.removeValue(forKey: "hooks")
            } else {
                json["hooks"] = hooks
            }
        }
    }

    internal static func registeredEvents(in hooks: [String: Any]) -> [String] {
        managedEvents.filter { event in
            guard let entries = hooks[event] as? [[String: Any]] else {
                return false
            }
            return entries.contains { ownsEntry($0) }
        }
    }

    internal static func unsupportedAliases(in aliases: [LaunchAlias]) -> [LaunchAlias] {
        aliases.filter { !$0.supportsClaudeHooks }
    }

    // MARK: - Private helpers

    private static func makeEntry(forEvent eventName: String) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                [
                    "type": "command",
                    "command": "\(hookScriptURL.path) \(eventName)",
                    "_id": hookCommandIdentifier
                ]
            ]
        ]
    }

    private static func ownsEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else {
            return false
        }
        return hooks.contains { hook in
            if (hook["_id"] as? String) == hookCommandIdentifier {
                return true
            }
            guard let command = hook["command"] as? String else {
                return false
            }
            return command.contains(hookScriptURL.path)
        }
    }

    private static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return (object as? [String: Any]) ?? [:]
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

        let outData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try outData.write(to: url, options: [.atomic])
    }
}
