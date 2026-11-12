@testable import VSVibe
import XCTest

/// Every test points the installer at a temp script path and temp Claude
/// config directories; the real `~/.vsvibe` and `~/.claude` are never touched.
@MainActor
internal final class HookInstallerTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    private var scriptURL: URL { directory.appendingPathComponent("hooks/claude-notify.sh") }
    private var configDir: URL { directory.appendingPathComponent("claude", isDirectory: true) }
    private var alias: LaunchAlias { LaunchAlias(command: "work", claudeConfigDir: configDir) }
    private var settingsURL: URL { configDir.appendingPathComponent("settings.json") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("hooks")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func readSettings() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func writeSettings(_ json: [String: Any]) throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: settingsURL)
    }

    private func hooks() throws -> [String: Any] {
        try XCTUnwrap(try readSettings()["hooks"] as? [String: Any])
    }

    // MARK: - Script

    internal func testWriteScriptCreatesExecutableScript() throws {
        XCTAssertFalse(HookInstaller.isScriptInstalled(at: scriptURL))
        try HookInstaller.writeScript(to: scriptURL)
        XCTAssertTrue(HookInstaller.isScriptInstalled(at: scriptURL))

        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("#!/usr/bin/env bash"))
        XCTAssertTrue(contents.contains("id: \(HookInstaller.hookCommandIdentifier)"))
        XCTAssertTrue(contents.contains("events.jsonl"))

        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
        XCTAssertEqual(permissions & 0o777, 0o755)
    }

    internal func testDefaultLocationsLiveUnderDotVSVibe() {
        XCTAssertEqual(HookInstaller.appDir.lastPathComponent, ".vsvibe")
        XCTAssertEqual(HookInstaller.hookScriptURL.lastPathComponent, "claude-notify.sh")
        XCTAssertEqual(HookInstaller.eventsFileURL, HookInstaller.appDir.appendingPathComponent("events.jsonl"))
        // Read-only probe of the real location; must agree with the URL-based check.
        XCTAssertEqual(
            HookInstaller.isScriptInstalled,
            HookInstaller.isScriptInstalled(at: HookInstaller.hookScriptURL)
        )
    }

    // MARK: - Install

    internal func testInstallWritesScriptAndRegistersStopAndNotification() throws {
        let plain = LaunchAlias(command: "plain", claudeConfigDir: nil)
        try HookInstaller.install(aliases: [alias, plain], scriptURL: scriptURL)

        XCTAssertTrue(HookInstaller.isScriptInstalled(at: scriptURL))
        let hooks = try hooks()
        XCTAssertEqual(Set(hooks.keys), ["Stop", "Notification"])
        let stopEntries = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 1)
        XCTAssertEqual(stopEntries.first?["matcher"] as? String, "")
        let command = try XCTUnwrap((stopEntries.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(command["type"] as? String, "command")
        XCTAssertEqual(command["_id"] as? String, HookInstaller.hookCommandIdentifier)
        XCTAssertEqual(command["command"] as? String, "\(HookInstaller.hookScriptURL.path) Stop")

        let status = HookInstaller.currentStatus(aliases: [alias, plain], scriptURL: scriptURL)
        XCTAssertTrue(status.scriptInstalled)
        XCTAssertEqual(status.aliases.map(\.id), ["work"])
        XCTAssertEqual(status.aliases.first?.registeredEvents, ["Stop", "Notification"])
        XCTAssertTrue(status.isFullyInstalled)
        XCTAssertFalse(status.isPartiallyInstalled)
    }

    internal func testInstallIsIdempotentAndKeepsForeignHooks() throws {
        let foreign: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "say done"]]]
        try writeSettings(["model": "opus", "hooks": ["Stop": [foreign]]])

        try HookInstaller.installInto(alias: alias)
        try HookInstaller.installInto(alias: alias)

        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        let stopEntries = try XCTUnwrap(try hooks()["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 2, "foreign hook plus exactly one VSVibe hook")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path + ".vsvibe.bak"))
    }

    internal func testInstallReplacesLegacyEntryMatchedByScriptPath() throws {
        let legacy: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": "\(HookInstaller.hookScriptURL.path) Stop"]]
        ]
        try writeSettings(["hooks": ["Stop": [legacy]]])
        try HookInstaller.installInto(alias: alias)
        let stopEntries = try XCTUnwrap(try hooks()["Stop"] as? [[String: Any]])
        XCTAssertEqual(stopEntries.count, 1)
    }

    internal func testInstallTreatsEmptyOrNonObjectSettingsAsEmpty() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try Data().write(to: settingsURL)
        try HookInstaller.installInto(alias: alias)
        XCTAssertEqual(Set(try hooks().keys), ["Stop", "Notification"])

        try Data("[1, 2]".utf8).write(to: settingsURL)
        try HookInstaller.installInto(alias: alias)
        XCTAssertEqual(Set(try hooks().keys), ["Stop", "Notification"])
    }

    internal func testAliasWithoutConfigDirIsSkipped() throws {
        let plain = LaunchAlias(command: "plain", claudeConfigDir: nil)
        try HookInstaller.installInto(alias: plain)
        try HookInstaller.uninstallFrom(alias: plain)
        XCTAssertEqual(HookInstaller.unsupportedAliases(in: [alias, plain]).map(\.command), ["plain"])
        XCTAssertTrue(HookInstaller.currentStatus(aliases: [plain], scriptURL: scriptURL).aliases.isEmpty)
    }

    // MARK: - Uninstall

    internal func testUninstallRemovesOnlyVSVibeEntries() throws {
        let foreign: [String: Any] = ["matcher": "", "hooks": [["type": "command", "command": "say done"]]]
        let ours: [String: Any] = ["hooks": [["_id": HookInstaller.hookCommandIdentifier]]]
        try writeSettings([
            "hooks": [
                "Stop": [foreign, ours],
                "Notification": [ours],
                "SubagentStop": [ours],
                "PreToolUse": [foreign]
            ]
        ])

        try HookInstaller.uninstall(aliases: [alias])

        let hooks = try hooks()
        XCTAssertEqual(Set(hooks.keys), ["Stop", "PreToolUse"])
        XCTAssertEqual((hooks["Stop"] as? [[String: Any]])?.count, 1)
    }

    internal func testUninstallDropsHooksKeyWhenNothingIsLeft() throws {
        try HookInstaller.install(aliases: [alias], scriptURL: scriptURL)
        try HookInstaller.uninstallFrom(alias: alias)
        XCTAssertNil(try readSettings()["hooks"])
        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)
        XCTAssertEqual(status.aliases.first?.registeredEvents, [])
        XCTAssertFalse(status.isFullyInstalled)
    }

    internal func testUninstallWithoutHooksLeavesSettingsAlone() throws {
        try writeSettings(["model": "opus"])
        try HookInstaller.uninstallFrom(alias: alias)
        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertNil(settings["hooks"])
    }

    // MARK: - Status

    internal func testRegisteredEventsIgnoresMalformedEntries() {
        let ours: [String: Any] = ["hooks": [["_id": HookInstaller.hookCommandIdentifier]]]
        let noHooksArray: [String: Any] = ["matcher": ""]
        let unrelated: [String: Any] = ["hooks": [["type": "command"]]]
        let events = HookInstaller.registeredEvents(in: [
            "Stop": [noHooksArray, unrelated],
            "Notification": "not-a-list",
            "SubagentStop": [ours]
        ])
        XCTAssertEqual(events, ["SubagentStop"])
    }

    internal func testStatusFlags() {
        let full = HookInstaller.AliasStatus(alias: alias, registeredEvents: ["Stop", "Notification"])
        let half = HookInstaller.AliasStatus(
            alias: LaunchAlias(command: "other", claudeConfigDir: configDir),
            registeredEvents: ["Stop"]
        )
        XCTAssertTrue(full.isInstalled)
        XCTAssertFalse(half.isInstalled)

        let partial = HookInstaller.Status(scriptInstalled: true, aliases: [full, half])
        XCTAssertFalse(partial.isFullyInstalled)
        XCTAssertTrue(partial.isPartiallyInstalled)

        XCTAssertFalse(HookInstaller.Status(scriptInstalled: true, aliases: []).isFullyInstalled)
        XCTAssertFalse(HookInstaller.Status(scriptInstalled: false, aliases: [full]).isFullyInstalled)
        XCTAssertFalse(HookInstaller.Status(scriptInstalled: false, aliases: [full, half]).isPartiallyInstalled)
    }

    internal func testStatusOfUnreadableSettingsHasNoEvents() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try Data("{broken".utf8).write(to: settingsURL)
        let status = HookInstaller.currentStatus(aliases: [alias], scriptURL: scriptURL)
        XCTAssertFalse(status.scriptInstalled)
        XCTAssertEqual(status.aliases.first?.registeredEvents, [])
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
