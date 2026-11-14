@testable import VSVibe
import XCTest

/// Detecting hooks installed by an older VSVibe (v1 script, no SessionStart)
/// and offering to update them. Paths point at a temp directory.
@MainActor
internal final class HookInstallerUpdateTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    private var scriptURL: URL { directory.appendingPathComponent("hooks/claude-notify.sh") }
    private var configDir: URL { directory.appendingPathComponent("claude", isDirectory: true) }
    private var alias: LaunchAlias { LaunchAlias(command: "work", claudeConfigDir: configDir) }
    private var settingsURL: URL { configDir.appendingPathComponent("settings.json") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("hook-update")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    /// What VSVibe v1 left behind: its script and only Stop + Notification.
    private func installV1() throws {
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env bash\n# id: vsvibe:claude-notify\nexit 0\n".utf8).write(to: scriptURL)
        let ours: [String: Any] = ["hooks": [["_id": HookInstaller.hookCommandIdentifier]]]
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [ours], "Notification": [ours]]])
            .write(to: settingsURL)
    }

    internal func testOldInstallNeedsUpdate() throws {
        try installV1()

        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)

        XCTAssertTrue(status.scriptInstalled)
        XCTAssertTrue(status.scriptOutdated)
        XCTAssertFalse(HookInstaller.isScriptCurrent(at: scriptURL))
        XCTAssertEqual(status.aliases.first?.registeredEvents, ["Stop", "Notification"])
        XCTAssertFalse(status.aliases.first?.isInstalled ?? true)
        XCTAssertFalse(status.isFullyInstalled)
        XCTAssertTrue(status.needsUpdate)
        XCTAssertEqual(status.installActionTitle, "Update Hooks")
    }

    internal func testReinstallingUpdatesAnOldInstall() throws {
        try installV1()

        try HookInstaller.install(aliases: [alias], scriptURL: scriptURL)

        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)
        XCTAssertFalse(status.scriptOutdated)
        XCTAssertTrue(status.isFullyInstalled)
        XCTAssertFalse(status.needsUpdate)
    }

    internal func testOutdatedScriptAloneNeedsUpdate() {
        let full = HookInstaller.AliasStatus(alias: alias, registeredEvents: HookInstaller.installedEvents)
        let status = HookInstaller.Status(scriptInstalled: true, aliases: [full], scriptOutdated: true)
        XCTAssertFalse(status.isFullyInstalled)
        XCTAssertTrue(status.needsUpdate)
        XCTAssertEqual(status.installActionTitle, "Update Hooks")
    }

    internal func testInstallActionTitles() {
        let full = HookInstaller.AliasStatus(alias: alias, registeredEvents: HookInstaller.installedEvents)
        let none = HookInstaller.AliasStatus(
            alias: LaunchAlias(command: "other", claudeConfigDir: configDir),
            registeredEvents: []
        )
        let missing = HookInstaller.Status(scriptInstalled: false, aliases: [none])
        XCTAssertEqual(missing.installActionTitle, "Install Hooks")
        let partial = HookInstaller.Status(scriptInstalled: true, aliases: [full, none])
        XCTAssertFalse(partial.needsUpdate)
        XCTAssertEqual(partial.installActionTitle, "Reinstall Hooks")
        XCTAssertFalse(HookInstaller.Status(scriptInstalled: false, aliases: [], scriptOutdated: true).needsUpdate)
    }

    internal func testMissingScriptIsNotCurrentOrOutdated() {
        XCTAssertFalse(HookInstaller.isScriptCurrent(at: scriptURL))
        XCTAssertFalse(HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL).scriptOutdated)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
