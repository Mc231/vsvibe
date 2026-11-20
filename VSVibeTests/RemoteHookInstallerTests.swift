@testable import VSVibe
import XCTest

/// Remote hook installation with a scripted fake ssh: probing the config dir,
/// state evaluation, failures, and the paths and scripts used.
internal final class RemoteHookInstallerTests: XCTestCase {
    private static let home = "/home/me"
    private let target = RemoteTarget(destination: "dev", command: "claudework --verbose")

    private var layout: RemoteHookLayout {
        get throws {
            try XCTUnwrap(RemoteHookLayout(home: Self.home, configDir: "/home/me/.claude"))
        }
    }

    private func probeOutput(definition: String? = nil) -> String {
        var output = "rc noise\n__VSVIBE_HOME__\(Self.home)\n"
        if let definition {
            output += "__VSVIBE_BEGIN__\n\(definition)\n__VSVIBE_END__\n"
        }
        return output
    }

    // MARK: - Probe and layout

    internal func testProbeScriptAsksTheInteractiveShellForTheAlias() {
        let script = RemoteHookInstaller.probeScript(forCommand: "claudework --verbose")
        XCTAssertTrue(script.hasPrefix(#"printf '%s%s\n' '__VSVIBE_HOME__' "$HOME"; "${SHELL:-/bin/sh}" -i -l -c "#))
        XCTAssertTrue(script.contains("alias '\\''claudework'\\''"))
        XCTAssertTrue(script.hasSuffix(" </dev/null 2>/dev/null; exit 0"))

        XCTAssertEqual(
            RemoteHookInstaller.probeScript(forCommand: "$(evil)"),
            #"printf '%s%s\n' '__VSVIBE_HOME__' "$HOME"; exit 0"#
        )
    }

    internal func testLayoutUsesTheAliasConfigDirOrTheDefault() throws {
        let aliased = RemoteHookInstaller.layout(
            fromProbeOutput: probeOutput(definition: #"alias claudework='CLAUDE_CONFIG_DIR=~/.claude-work claude'"#),
            command: "claudework --verbose"
        )
        XCTAssertEqual(aliased?.configDir, "/home/me/.claude-work")
        XCTAssertEqual(aliased?.home, Self.home)

        let plain = RemoteHookInstaller.layout(fromProbeOutput: probeOutput(definition: ""), command: "claude")
        XCTAssertEqual(plain?.configDir, "/home/me/.claude")

        XCTAssertNil(RemoteHookInstaller.layout(fromProbeOutput: "no marker", command: "claude"))
        XCTAssertNil(RemoteHookInstaller.layout(fromProbeOutput: "__VSVIBE_HOME__relative", command: "claude"))
        XCTAssertEqual(
            RemoteHookInstaller.layout(fromProbeOutput: "__VSVIBE_HOME__/", command: "")?.configDir,
            "/.claude"
        )
    }

    internal func testLayoutPathsAndScripts() throws {
        let layout = try layout
        XCTAssertEqual(layout.scriptPath, "/home/me/.vsvibe/hooks/claude-notify.sh")
        XCTAssertEqual(layout.settingsPath, "/home/me/.claude/settings.json")
        XCTAssertEqual(layout.settingsBackupPath, "/home/me/.claude/settings.json.vsvibe.bak")
        XCTAssertEqual(layout.scriptCommand, layout.scriptPath)
        XCTAssertEqual(
            layout.writeScriptScript,
            "mkdir -p '/home/me/.vsvibe/hooks' && cat > '/home/me/.vsvibe/hooks/claude-notify.sh' "
                + "&& chmod 755 '/home/me/.vsvibe/hooks/claude-notify.sh'"
        )
        XCTAssertTrue(layout.writeSettingsScript.contains("cp -p '/home/me/.claude/settings.json' "))
        XCTAssertEqual(
            RemoteHookLayout.readScript("/a b"),
            "if [ -f '/a b' ]; then cat '/a b'; else exit 3; fi"
        )

        let spaced = try XCTUnwrap(RemoteHookLayout(home: "/Users/me too/", configDir: "/c"))
        XCTAssertEqual(spaced.scriptCommand, "'/Users/me too/.vsvibe/hooks/claude-notify.sh'")
        XCTAssertNil(RemoteHookLayout(home: "home", configDir: "/c"))
        XCTAssertNil(RemoteHookLayout(home: "/h", configDir: "/c\nd"))
    }

    internal func testStateEvaluation() throws {
        let layout = try layout
        let script = Data(HookScript.contents.utf8)
        let installed = HookSettings.installing(
            into: [:],
            scriptPath: layout.scriptPath,
            scriptCommand: layout.scriptPath
        )
        let old = Data("old".utf8)

        XCTAssertEqual(RemoteHookInstaller.state(script: script, settings: installed, layout: layout), .installed)
        XCTAssertEqual(RemoteHookInstaller.state(script: old, settings: installed, layout: layout), .outdated)
        XCTAssertEqual(RemoteHookInstaller.state(script: script, settings: [:], layout: layout), .outdated)
        XCTAssertEqual(RemoteHookInstaller.state(script: nil, settings: installed, layout: layout), .outdated)
        XCTAssertEqual(RemoteHookInstaller.state(script: nil, settings: [:], layout: layout), .missing)
    }

    // MARK: - Operations with a fake host

    /// A fake host: answers the probe, serves `files` and records writes.
    private func host(files: [String: String], probe: String? = nil) -> FakeRemoteRunner {
        let probeOutput = probe ?? self.probeOutput()
        return FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data(probeOutput.utf8))
            }
            if script.hasPrefix("if [ -f") {
                let file = files.first { script.contains("'\($0.key)'") }
                return file.map { RemoteCommandResult(status: 0, output: Data($0.value.utf8)) }
                    ?? RemoteCommandResult(status: 3)
            }
            return RemoteCommandResult(status: 0)
        }
    }

    internal func testStatusReportsWhatTheHostHas() async {
        let missing = await RemoteHookInstaller(runner: host(files: [:])).status(of: target)
        XCTAssertEqual(missing, RemoteHookReport(state: .missing, configDir: "/home/me/.claude"))

        let script = "/home/me/.vsvibe/hooks/claude-notify.sh"
        let outdated = await RemoteHookInstaller(runner: host(files: [script: "old"])).status(of: target)
        XCTAssertEqual(outdated.state, .outdated)

        let broken = host(files: ["/home/me/.claude/settings.json": "{oops"])
        let invalid = await RemoteHookInstaller(runner: broken).status(of: target)
        let message = "/home/me/.claude/settings.json is not valid JSON; fix it and try again."
        XCTAssertEqual(invalid.state, .failed(message))
    }

    internal func testInstallWritesTheScriptAndMergesSettings() async throws {
        let existing = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"audit"}]}]},"model":"opus"}"#
        let runner = host(files: ["/home/me/.claude/settings.json": existing])

        let report = await RemoteHookInstaller(runner: runner).install(on: target)

        XCTAssertEqual(report, RemoteHookReport(state: .installed, configDir: "/home/me/.claude"))
        let calls = runner.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls[1].script, try layout.writeScriptScript)
        XCTAssertEqual(calls[1].input, Data(HookScript.contents.utf8))
        XCTAssertEqual(calls[3].script, try layout.writeSettingsScript)
        let written = try HookSettings.object(from: try XCTUnwrap(calls[3].input))
        XCTAssertEqual(written["model"] as? String, "opus")
        XCTAssertEqual(
            HookSettings.registeredEvents(inSettings: written, scriptPath: try layout.scriptPath),
            ["SessionStart", "Stop", "Notification"]
        )
        let stop = (written["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2)
        XCTAssertTrue(calls.allSatisfy { $0.arguments.contains("BatchMode=yes") && $0.arguments.contains("dev") })
    }

    internal func testInstallLeavesInvalidSettingsAlone() async {
        let runner = host(files: ["/home/me/.claude/settings.json": "{oops"])

        let report = await RemoteHookInstaller(runner: runner).install(on: target)

        let message = "/home/me/.claude/settings.json is not valid JSON; fix it and try again."
        XCTAssertEqual(report.state, .failed(message))
        XCTAssertEqual(runner.calls.count, 3)
    }

    internal func testUnreachableAndFailingHosts() async {
        let down = FakeRemoteRunner { _, _ in RemoteCommandResult(status: 255, errorOutput: "Connection refused\n") }
        let unreachable = await RemoteHookInstaller(runner: down).install(on: target)
        XCTAssertEqual(unreachable, RemoteHookReport(state: .unreachable("Connection refused")))

        let noHome = FakeRemoteRunner { _, _ in RemoteCommandResult(status: 0, output: Data("?".utf8)) }
        let homeless = await RemoteHookInstaller(runner: noHome).status(of: target)
        XCTAssertEqual(homeless.state, .failed("Could not determine the remote home directory."))

        let invalid = await RemoteHookInstaller(runner: down).status(of: RemoteTarget(destination: "-x"))
        XCTAssertEqual(invalid.state, .failed("The host can't start with \"-\"."))
        XCTAssertEqual(down.calls.count, 1)
    }

    internal func testFailingStepsAreReported() async {
        let probe = probeOutput()
        let readOnly = FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data(probe.utf8))
            }
            return RemoteCommandResult(status: 1, errorOutput: "Permission denied")
        }
        let installer = RemoteHookInstaller(runner: readOnly)

        let install = await installer.install(on: target)
        XCTAssertEqual(install, RemoteHookReport(state: .failed("Permission denied"), configDir: "/home/me/.claude"))
        let status = await installer.status(of: target)
        XCTAssertEqual(status.state, .failed("Permission denied"))
    }

    internal func testSettingsReadOrWriteFailuresAfterTheScript() async {
        let probe = probeOutput()
        let failsSettingsRead = FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data(probe.utf8))
            }
            return RemoteCommandResult(status: script.hasPrefix("if [ -f") ? 9 : 0, errorOutput: "io")
        }
        let readFailure = await RemoteHookInstaller(runner: failsSettingsRead).install(on: target)
        XCTAssertEqual(readFailure.state, .failed("io"))

        let failsSettingsWrite = FakeRemoteRunner { script, _ in
            if script.hasPrefix("printf") {
                return RemoteCommandResult(status: 0, output: Data(probe.utf8))
            }
            if script.hasPrefix("if [ -f") {
                return RemoteCommandResult(status: 3)
            }
            return RemoteCommandResult(status: script.contains("settings.json") ? 1 : 0, errorOutput: "disk full")
        }
        let writeFailure = await RemoteHookInstaller(runner: failsSettingsWrite).install(on: target)
        XCTAssertEqual(writeFailure.state, .failed("disk full"))
    }

    deinit {
        // Stateless tests.
    }
}
