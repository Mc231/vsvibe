import Foundation

/// The VSVibe hook entries in a Claude `settings.json`, as pure functions over
/// its JSON object. `HookInstaller` applies them to local files; remote hook
/// installation (`RemoteHookInstaller`) to a file read and written over ssh.
/// Entries of other tools are left untouched; VSVibe's own are recognised by
/// their `_id` or by a command naming the hook script.
internal enum HookSettings {
    /// Events the installer recognises (and cleans up) as its own.
    private static let managedEvents = ["SessionStart", "Stop", "Notification", "SubagentStop"]

    /// The settings object in `data`: empty data, or JSON that is not an
    /// object, is an empty object. Throws on malformed JSON.
    internal static func object(from data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return (object as? [String: Any]) ?? [:]
    }

    /// `json` as written back to `settings.json` (pretty-printed, sorted keys).
    internal static func data(of json: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    /// `json` with one VSVibe entry per installed event, replacing older
    /// VSVibe entries. `scriptCommand` is how the hook command names the
    /// script (`<scriptCommand> <event>`); `scriptPath` recognises old entries.
    internal static func installing(
        into json: [String: Any],
        scriptPath: String,
        scriptCommand: String
    ) -> [String: Any] {
        var json = json
        var hooks = (json["hooks"] as? [String: Any]) ?? [:]
        for event in HookInstaller.installedEvents {
            var entries = (hooks[event] as? [[String: Any]]) ?? []
            entries.removeAll { ownsEntry($0, scriptPath: scriptPath) }
            entries.append(makeEntry(forEvent: event, scriptCommand: scriptCommand))
            hooks[event] = entries
        }
        json["hooks"] = hooks
        return json
    }

    /// `json` without VSVibe entries; events (and `hooks`) left empty are removed.
    internal static func uninstalling(from json: [String: Any], scriptPath: String) -> [String: Any] {
        guard var hooks = json["hooks"] as? [String: Any] else {
            return json
        }
        var json = json
        for event in managedEvents {
            guard var entries = hooks[event] as? [[String: Any]] else {
                continue
            }
            entries.removeAll { ownsEntry($0, scriptPath: scriptPath) }
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
        return json
    }

    /// The managed events that have a VSVibe entry in `hooks`.
    internal static func registeredEvents(in hooks: [String: Any], scriptPath: String) -> [String] {
        managedEvents.filter { event in
            guard let entries = hooks[event] as? [[String: Any]] else {
                return false
            }
            return entries.contains { ownsEntry($0, scriptPath: scriptPath) }
        }
    }

    /// The managed events registered in a whole settings object.
    internal static func registeredEvents(inSettings json: [String: Any], scriptPath: String) -> [String] {
        (json["hooks"] as? [String: Any]).map { registeredEvents(in: $0, scriptPath: scriptPath) } ?? []
    }

    private static func makeEntry(forEvent eventName: String, scriptCommand: String) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                [
                    "type": "command",
                    "command": "\(scriptCommand) \(eventName)",
                    "_id": HookInstaller.hookCommandIdentifier
                ]
            ]
        ]
    }

    private static func ownsEntry(_ entry: [String: Any], scriptPath: String) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else {
            return false
        }
        return hooks.contains { hook in
            if (hook["_id"] as? String) == HookInstaller.hookCommandIdentifier {
                return true
            }
            guard let command = hook["command"] as? String else {
                return false
            }
            return command.contains(scriptPath)
        }
    }
}
