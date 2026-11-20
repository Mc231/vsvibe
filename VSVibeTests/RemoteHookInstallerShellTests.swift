@testable import VSVibe
import XCTest

/// Remote hook installation end to end against a real shell: the "host" is
/// `/bin/sh` with `HOME` pointing at a temporary directory (and bash as the
/// login shell, whose profile defines the Claude alias), so the probe, read
/// and write scripts really run.
internal final class RemoteHookInstallerShellTests: XCTestCase {
    /// Runs the ssh remote command locally, as the remote login shell would.
    private struct LocalHost: RemoteShellRunning {
        let home: URL

        func run(arguments: [String], input: Data?) async -> RemoteCommandResult {
            let environment = "HOME=\(SSHCommand.shellQuoted(home.path)); export HOME; "
                + "SHELL=/bin/bash; export SHELL; "
            let runner = SSHCommandRunner(executableURL: URL(fileURLWithPath: "/bin/sh"), controlDirectory: nil)
            return await runner.run(arguments: ["-c", environment + (arguments.last ?? "")], input: input)
        }
    }

    private var home = TestSupport.placeholderURL
    private let target = RemoteTarget(destination: "dev", command: "claudework")

    private var configDir: URL {
        home.appendingPathComponent(".claude-work", isDirectory: true)
    }

    override internal func setUp() {
        super.setUp()
        home = TestSupport.makeTempDir("remote-home")
        let profile = #"alias claudework='CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude'"# + "\n"
        try? profile.write(to: home.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)
    }

    override internal func tearDown() {
        TestSupport.remove(home)
        super.tearDown()
    }

    internal func testInstallIntoTheAliasConfigDirKeepsUserHooks() async throws {
        let installer = RemoteHookInstaller(runner: LocalHost(home: home))
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let settingsURL = configDir.appendingPathComponent("settings.json")
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"audit"}]}]}}"#.utf8).write(to: settingsURL)

        let before = await installer.status(of: target)
        XCTAssertEqual(before, RemoteHookReport(state: .missing, configDir: configDir.path))

        let installed = await installer.install(on: target)
        XCTAssertEqual(installed.state, .installed)

        let scriptURL = home.appendingPathComponent(".vsvibe/hooks/claude-notify.sh")
        XCTAssertEqual(try String(contentsOf: scriptURL, encoding: .utf8), HookScript.contents)
        let permissions = try FileManager.default.attributesOfItem(atPath: scriptURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o755)
        let settings = try HookSettings.object(from: Data(contentsOf: settingsURL))
        XCTAssertEqual(
            HookSettings.registeredEvents(inSettings: settings, scriptPath: scriptURL.path),
            ["SessionStart", "Stop", "Notification"]
        )
        let stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 2)
        let backup = configDir.appendingPathComponent("settings.json.vsvibe.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        let after = await installer.status(of: target)
        XCTAssertEqual(after, RemoteHookReport(state: .installed, configDir: configDir.path))

        try Data("#!/bin/sh\n".utf8).write(to: scriptURL)
        let outdated = await installer.status(of: target)
        XCTAssertEqual(outdated.state, .outdated)
    }

    internal func testPlainCommandUsesTheDefaultConfigDir() async throws {
        let installer = RemoteHookInstaller(runner: LocalHost(home: home))

        let report = await installer.install(on: RemoteTarget(destination: "dev", command: "claude"))

        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        let defaultDir = home.appendingPathComponent(".claude").path
        XCTAssertEqual(report, RemoteHookReport(state: .installed, configDir: defaultDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        let backup = home.appendingPathComponent(".claude/settings.json.vsvibe.bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    deinit {
        // Stateless tests.
    }
}
