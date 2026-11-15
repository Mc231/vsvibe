import Foundation

/// Reads the Claude config dir out of a shell alias or function definition,
/// as printed by `ShellAliasResolver`'s script, e.g. zsh's
/// `claudework='CLAUDE_CONFIG_DIR="$HOME/.claude-work" /usr/local/bin/claude'`,
/// bash's `alias claudework='…'` or a function body with
/// `export CLAUDE_CONFIG_DIR=~/.claude-work`.
internal enum ShellAliasParser {
    internal static let configDirVariable = "CLAUDE_CONFIG_DIR"
    internal static let beginMarker = "__VSVIBE_BEGIN__"
    internal static let endMarker = "__VSVIBE_END__"

    /// The text between the begin and end marker lines (anything an rc file
    /// prints around them is ignored), or nil when a marker is missing.
    internal static func markedOutput(_ output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(of: beginMarker),
            let end = lines[(begin + 1)...].firstIndex(of: endMarker)
        else {
            return nil
        }
        return lines[(begin + 1)..<end].joined(separator: "\n")
    }

    /// The config dir assigned to `CLAUDE_CONFIG_DIR` in the definition of
    /// `command` (`$HOME`, `${HOME}` and a leading `~` expanded to `home`).
    /// Nil when there is no assignment or its value is not an absolute path
    /// after expansion (e.g. it uses another variable).
    internal static func claudeConfigDir(inDefinition definition: String, command: String, home: String) -> URL? {
        let body = definition
            .components(separatedBy: "\n")
            .map { aliasValue(inLine: $0, command: command) }
            .joined(separator: "\n")
        let prefix = configDirVariable + "="
        guard let assignment = ShellWords.split(body, home: home).first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let value = expandingTilde(String(assignment.dropFirst(prefix.count)), home: home)
        guard value.hasPrefix("/"),
            !value.contains("$"),
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    /// For an alias line (`name=value` or `alias name=value`) the alias value
    /// with its outer quoting removed; any other line unchanged.
    private static func aliasValue(inLine line: String, command: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("alias ") {
            text = String(text.dropFirst("alias ".count))
        }
        guard text.hasPrefix(command + "=") else {
            return line
        }
        return ShellWords.split(String(text.dropFirst(command.count + 1))).joined(separator: " ")
    }

    /// Assignments expand a leading `~` / `~/` too (`VAR=~/dir`).
    private static func expandingTilde(_ value: String, home: String) -> String {
        if value == "~" || value.hasPrefix("~/") {
            return home + value.dropFirst()
        }
        return value
    }
}
