import Foundation

/// Asks the user's interactive login shell how a command is defined (an alias
/// from `~/.zshrc`, or a function) and reads the `CLAUDE_CONFIG_DIR` it sets,
/// so a shell alias for another Claude account can be offered for
/// registration. Only names accepted by `ShellCommandName` are ever put into
/// the script. Blocking (spawns a shell, `ShellProbe` timeout): call off the
/// main thread.
internal struct ShellAliasResolver: Sendable {
    /// The real shell, bounded by `ShellProbe.defaultTimeout`.
    internal static let live = Self { shell, script in
        let arguments = ShellProbe.interactiveLoginArguments + [script]
        guard case let .exited(_, output) = ShellProbe.run(shell: shell, arguments: arguments, captureOutput: true)
        else {
            return nil
        }
        return output
    }

    /// Runs `script` in `shell` and returns its stdout, or nil when the shell
    /// failed to start or timed out.
    internal var runScript: @Sendable (_ shell: String, _ script: String) -> String?

    /// The script printing the definition of `command` between the parser's
    /// markers: `alias <name>`, else (a function) `typeset -f <name>`. Nil for
    /// an unsafe name.
    internal static func script(for command: String) -> String? {
        guard let name = ShellCommandName.quoted(command) else {
            return nil
        }
        let begin = ShellAliasParser.beginMarker
        let end = ShellAliasParser.endMarker
        return "printf '%s\\n' '\(begin)'; alias \(name) 2>/dev/null || typeset -f \(name) 2>/dev/null; "
            + "printf '%s\\n' '\(end)'"
    }

    /// The Claude config dir `command` sets via `CLAUDE_CONFIG_DIR`, or nil
    /// (not an alias/function, no assignment, unsafe name, shell timed out).
    internal func claudeConfigDir(
        forCommand command: String,
        shell: String,
        home: String = NSHomeDirectory()
    ) -> URL? {
        guard let script = Self.script(for: command),
            let output = runScript(shell, script),
            let definition = ShellAliasParser.markedOutput(output)
        else {
            return nil
        }
        return ShellAliasParser.claudeConfigDir(inDefinition: definition, command: command, home: home)
    }
}
