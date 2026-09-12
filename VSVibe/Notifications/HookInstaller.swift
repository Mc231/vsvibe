import Foundation

/// Manages installing/uninstalling the VSVibe Claude hook script and entries in
/// each Claude alias's `settings.json` (each alias may use its own
/// `CLAUDE_CONFIG_DIR`).
@MainActor
enum HookInstaller {
    static let appDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".vsvibe", isDirectory: true)
    }()

    static let hookScriptURL: URL = appDir.appendingPathComponent("hooks/claude-notify.sh")
    static let eventsFileURL: URL = appDir.appendingPathComponent("events.jsonl")
    static let hookCommandIdentifier = "vsvibe:claude-notify"

    private static let scriptContents: String = #"""
#!/usr/bin/env bash
# Installed by VSVibe — appends a JSON line per Claude hook event.
# id: vsvibe:claude-notify
set -uo pipefail

EVENT="${1:-Unknown}"
EVENTS_FILE="${HOME}/.vsvibe/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"

TS=$(date +%s)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
PAYLOAD=$(cat 2>/dev/null || true)

esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g'
}

MSG=""
if [ -n "$PAYLOAD" ]; then
  if command -v python3 >/dev/null 2>&1; then
    MSG=$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json
try:
  d=json.loads(sys.stdin.read())
  print(d.get("message",""))
except Exception:
  pass' 2>/dev/null || true)
  fi
fi

ESC_PROJECT=$(esc "$PROJECT_DIR")
ESC_MSG=$(esc "$MSG")

LINE="{\"event\":\"${EVENT}\",\"projectDir\":\"${ESC_PROJECT}\",\"ts\":${TS},\"message\":\"${ESC_MSG}\"}"
printf '%s\n' "$LINE" >> "$EVENTS_FILE"

exit 0
"""#

    // MARK: - Status

    struct AliasStatus: Equatable, Identifiable {
        let alias: LaunchAlias
        let registeredEvents: [String]

        var id: String { alias.id }
        var isInstalled: Bool {
            registeredEvents.contains("Stop") && registeredEvents.contains("Notification")
        }
    }

    struct Status: Equatable {
        let scriptInstalled: Bool
        let aliases: [AliasStatus]

        var isFullyInstalled: Bool {
            scriptInstalled && !aliases.isEmpty && aliases.allSatisfy(\.isInstalled)
        }

        var isPartiallyInstalled: Bool {
            scriptInstalled && aliases.contains(where: \.isInstalled) && !isFullyInstalled
        }
    }

    static var isScriptInstalled: Bool {
        FileManager.default.fileExists(atPath: hookScriptURL.path)
    }

    static func currentStatus() -> Status {
        let scriptOK = isScriptInstalled
        let aliasStatuses: [AliasStatus] = LaunchCommandResolver.hookCapableAliases.compactMap { alias in
            guard let settingsURL = alias.settingsURL else { return nil }
            let events = (try? readSettings(at: settingsURL))
                .flatMap { ($0["hooks"] as? [String: Any]).map(registeredEvents(in:)) } ?? []
            return AliasStatus(alias: alias, registeredEvents: events)
        }
        return Status(scriptInstalled: scriptOK, aliases: aliasStatuses)
    }

    // MARK: - Install / Uninstall

    static func writeScript() throws {
        let fm = FileManager.default
        let dir = hookScriptURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try scriptContents.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: hookScriptURL.path)
    }

    static func install() throws {
        try writeScript()
        for alias in LaunchCommandResolver.hookCapableAliases {
            try installInto(alias: alias)
        }
    }

    static func installInto(alias: LaunchAlias) throws {
        guard let settingsURL = alias.settingsURL else { return }
        try mutateSettings(at: settingsURL) { json in
            var hooks = (json["hooks"] as? [String: Any]) ?? [:]
            for event in ["Stop", "Notification"] {
                var arr = (hooks[event] as? [[String: Any]]) ?? []
                arr.removeAll { ownsEntry($0) }
                arr.append(makeEntry(forEvent: event))
                hooks[event] = arr
            }
            json["hooks"] = hooks
        }
    }

    static func uninstall() throws {
        for alias in LaunchCommandResolver.hookCapableAliases {
            try uninstallFrom(alias: alias)
        }
    }

    static func uninstallFrom(alias: LaunchAlias) throws {
        guard let settingsURL = alias.settingsURL else { return }
        try mutateSettings(at: settingsURL) { json in
            guard var hooks = json["hooks"] as? [String: Any] else { return }
            for event in ["Stop", "Notification", "SubagentStop"] {
                guard var arr = hooks[event] as? [[String: Any]] else { continue }
                arr.removeAll { ownsEntry($0) }
                if arr.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = arr
                }
            }
            if hooks.isEmpty {
                json.removeValue(forKey: "hooks")
            } else {
                json["hooks"] = hooks
            }
        }
    }

    static func registeredEvents(in hooks: [String: Any]) -> [String] {
        var result: [String] = []
        for event in ["Stop", "Notification", "SubagentStop"] {
            if let entries = hooks[event] as? [[String: Any]],
               entries.contains(where: { ownsEntry($0) }) {
                result.append(event)
            }
        }
        return result
    }

    // MARK: - Private helpers

    static func unsupportedAliases() -> [LaunchAlias] {
        LaunchCommandResolver.aliases.filter { !$0.supportsClaudeHooks }
    }

    private static func makeEntry(forEvent eventName: String) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": "\(hookScriptURL.path) \(eventName)",
                "_id": hookCommandIdentifier
            ]]
        ]
    }

    private static func ownsEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        for hook in hooks {
            if (hook["_id"] as? String) == hookCommandIdentifier { return true }
            if let cmd = hook["command"] as? String, cmd.contains(hookScriptURL.path) {
                return true
            }
        }
        return false
    }

    private static func readSettings(at url: URL) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return (obj as? [String: Any]) ?? [:]
    }

    private static func mutateSettings(at url: URL, _ mutate: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        var json: [String: Any] = (try? readSettings(at: url)) ?? [:]

        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("vsvibe.bak")
            _ = try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }

        mutate(&json)

        let outData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try outData.write(to: url, options: [.atomic])
    }
}
