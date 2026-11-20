import Foundation

/// Checks, installs and updates the VSVibe Claude hooks on a remote project's
/// host over ssh (`RemoteSSH`, no prompts): the stock hook script
/// (`HookScript`) at `~/.vsvibe/hooks/claude-notify.sh` and its entries in the
/// `settings.json` of the Claude config dir the project's command uses: the
/// `CLAUDE_CONFIG_DIR` a remote shell alias of that name sets (asked from the
/// remote interactive login shell, read with `ShellAliasParser`), else
/// `~/.claude`. `settings.json` is merged exactly like locally
/// (`HookSettings`), keeping the user's other hooks and a `.vsvibe.bak` copy.
internal struct RemoteHookInstaller: Sendable {
    private enum FileRead {
        case contents(Data)
        case failed(RemoteCommandResult)
        case missing
    }

    private enum Location {
        case failed(RemoteHookReport)
        case found(SSHConnection, RemoteHookLayout)
    }

    private static let homeMarker = "__VSVIBE_HOME__"
    private static let defaultConfigDirName = ".claude"

    internal let runner: any RemoteShellRunning

    // MARK: - Probe

    /// Prints the remote home (after `homeMarker`) and, for a command whose
    /// base word is a plain name, its alias / function definition as the
    /// remote interactive login shell sees it (between the parser's markers).
    internal static func probeScript(forCommand command: String) -> String {
        var script = #"printf '%s%s\n' '\#(homeMarker)' "$HOME""#
        if let aliasScript = ShellAliasResolver.script(for: LaunchCommandResolver.baseCommand(of: command)) {
            script += #"; "${SHELL:-/bin/sh}" -i -l -c "# + SSHCommand.shellQuoted(aliasScript)
                + " </dev/null 2>/dev/null"
        }
        return script + "; exit 0"
    }

    /// Where the hooks go, from the probe's output: the alias's config dir
    /// when it sets one, else `<home>/.claude`. Nil without a valid home.
    internal static func layout(fromProbeOutput output: String, command: String) -> RemoteHookLayout? {
        let lines = output.components(separatedBy: "\n")
        guard let homeLine = lines.first(where: { $0.hasPrefix(homeMarker) }) else {
            return nil
        }
        let home = String(homeLine.dropFirst(homeMarker.count))
        guard RemoteHookLayout.isValidPath(home) else {
            return nil
        }
        let name = LaunchCommandResolver.baseCommand(of: command)
        let aliasConfigDir = ShellAliasParser.markedOutput(output).flatMap { definition in
            ShellAliasParser.claudeConfigDir(inDefinition: definition, command: name, home: home)
        }
        let configDir = aliasConfigDir?.path
            ?? URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(defaultConfigDirName).path
        return RemoteHookLayout(home: home, configDir: configDir)
    }

    /// The hook state for the files found: current script and every event
    /// registered is installed; nothing of VSVibe's is missing; anything else
    /// is outdated.
    internal static func state(script: Data?, settings: [String: Any], layout: RemoteHookLayout) -> RemoteHookState {
        let events = HookSettings.registeredEvents(inSettings: settings, scriptPath: layout.scriptPath)
        let complete = HookInstaller.installedEvents.allSatisfy(events.contains)
        if script == Data(HookScript.contents.utf8), complete {
            return .installed
        }
        return script == nil && events.isEmpty ? .missing : .outdated
    }

    // MARK: - Reports

    /// The settings object of a read: empty when the file is missing. Throws
    /// when it is not valid JSON (or the read failed).
    private static func settingsObject(_ read: FileRead) throws -> [String: Any] {
        switch read {
        case .contents(let data):
            return try HookSettings.object(from: data)

        case .missing:
            return [:]

        case .failed(let result):
            throw RemoteHookInstallerError.readFailed(result.errorSummary)
        }
    }

    private static func failure(_ result: RemoteCommandResult, configDir: String?) -> RemoteHookReport {
        let state: RemoteHookState = result.isSSHFailure
            ? .unreachable(result.errorSummary)
            : .failed(result.errorSummary)
        return RemoteHookReport(state: state, configDir: configDir)
    }

    private static func invalidSettings(_ layout: RemoteHookLayout) -> RemoteHookReport {
        RemoteHookReport(
            state: .failed("\(layout.settingsPath) is not valid JSON; fix it and try again."),
            configDir: layout.configDir
        )
    }

    // MARK: - Operations

    /// The hooks' state on the host of `target`.
    internal func status(of target: RemoteTarget) async -> RemoteHookReport {
        let connection: SSHConnection
        let layout: RemoteHookLayout
        switch await locate(target) {
        case .failed(let report):
            return report

        case let .found(foundConnection, foundLayout):
            connection = foundConnection
            layout = foundLayout
        }
        let script = await read(layout.scriptPath, on: connection)
        let settings = await read(layout.settingsPath, on: connection)
        switch (script, settings) {
        case (.failed(let result), _), (_, .failed(let result)):
            return Self.failure(result, configDir: layout.configDir)

        default:
            guard let settingsObject = try? Self.settingsObject(settings) else {
                return Self.invalidSettings(layout)
            }
            var scriptData: Data?
            if case .contents(let data) = script {
                scriptData = data
            }
            let state = Self.state(script: scriptData, settings: settingsObject, layout: layout)
            return RemoteHookReport(state: state, configDir: layout.configDir)
        }
    }

    /// Writes the current hook script and registers it in `settings.json` on
    /// the host of `target`. A `settings.json` that is not valid JSON is left
    /// alone (reported as a failure) rather than overwritten.
    internal func install(on target: RemoteTarget) async -> RemoteHookReport {
        let connection: SSHConnection
        let layout: RemoteHookLayout
        switch await locate(target) {
        case .failed(let report):
            return report

        case let .found(foundConnection, foundLayout):
            connection = foundConnection
            layout = foundLayout
        }
        let script = Data(HookScript.contents.utf8)
        let wroteScript = await run(layout.writeScriptScript, on: connection, input: script)
        guard wroteScript.status == 0 else {
            return Self.failure(wroteScript, configDir: layout.configDir)
        }
        let current = await read(layout.settingsPath, on: connection)
        if case .failed(let result) = current {
            return Self.failure(result, configDir: layout.configDir)
        }
        guard let settings = try? Self.settingsObject(current) else {
            return Self.invalidSettings(layout)
        }
        let merged = HookSettings.installing(
            into: settings,
            scriptPath: layout.scriptPath,
            scriptCommand: layout.scriptCommand
        )
        guard let data = try? HookSettings.data(of: merged) else {
            return RemoteHookReport(state: .failed("Could not encode settings.json."), configDir: layout.configDir)
        }
        let wroteSettings = await run(layout.writeSettingsScript, on: connection, input: data)
        guard wroteSettings.status == 0 else {
            return Self.failure(wroteSettings, configDir: layout.configDir)
        }
        return RemoteHookReport(state: .installed, configDir: layout.configDir)
    }

    // MARK: - Steps

    /// The connection and hook layout of `target`, or the report explaining
    /// why there is none.
    private func locate(_ target: RemoteTarget) async -> Location {
        guard let connection = SSHConnection(target: target) else {
            let message = SSHCommand.validationError(of: target)?.message ?? "Invalid host."
            return .failed(RemoteHookReport(state: .failed(message)))
        }
        let probe = await run(Self.probeScript(forCommand: target.command), on: connection, input: nil)
        if probe.isSSHFailure {
            return .failed(Self.failure(probe, configDir: nil))
        }
        guard let layout = Self.layout(fromProbeOutput: probe.outputText, command: target.command) else {
            return .failed(RemoteHookReport(state: .failed("Could not determine the remote home directory.")))
        }
        return .found(connection, layout)
    }

    private func read(_ path: String, on connection: SSHConnection) async -> FileRead {
        let result = await run(RemoteHookLayout.readScript(path), on: connection, input: nil)
        switch result.status {
        case 0:
            return .contents(result.output)

        case RemoteHookLayout.missingFileStatus:
            return .missing

        default:
            return .failed(result)
        }
    }

    private func run(_ script: String, on connection: SSHConnection, input: Data?) async -> RemoteCommandResult {
        await runner.run(arguments: RemoteSSH.commandArguments(for: connection, script: script), input: input)
    }
}
