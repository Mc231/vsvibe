@testable import VSVibe
import XCTest

/// The pure `settings.json` merge shared by local and remote hook installation.
internal final class HookSettingsTests: XCTestCase {
    private let scriptPath = "/home/me/.vsvibe/hooks/claude-notify.sh"

    private var userHook: [String: Any] {
        ["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/local/bin/audit"]]]
    }

    private func commands(_ json: [String: Any], event: String) -> [String] {
        let hooks = json["hooks"] as? [String: Any]
        let entries = hooks?[event] as? [[String: Any]] ?? []
        return entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    internal func testInstallAddsEveryEventAndKeepsUserHooks() {
        let json: [String: Any] = ["model": "opus", "hooks": ["Stop": [userHook]]]

        let merged = HookSettings.installing(into: json, scriptPath: scriptPath, scriptCommand: scriptPath)

        XCTAssertEqual(merged["model"] as? String, "opus")
        XCTAssertEqual(commands(merged, event: "Stop"), ["/usr/local/bin/audit", "\(scriptPath) Stop"])
        XCTAssertEqual(commands(merged, event: "SessionStart"), ["\(scriptPath) SessionStart"])
        XCTAssertEqual(commands(merged, event: "Notification"), ["\(scriptPath) Notification"])
        XCTAssertEqual(
            HookSettings.registeredEvents(inSettings: merged, scriptPath: scriptPath),
            ["SessionStart", "Stop", "Notification"]
        )
    }

    internal func testReinstallReplacesOldEntriesInsteadOfDuplicating() {
        let old: [String: Any] = ["hooks": [["type": "command", "command": "\(scriptPath) Stop"]]]
        let json: [String: Any] = ["hooks": ["Stop": [old, userHook]]]

        let once = HookSettings.installing(into: json, scriptPath: scriptPath, scriptCommand: "'quoted' path")
        let twice = HookSettings.installing(into: once, scriptPath: scriptPath, scriptCommand: "'quoted' path")

        XCTAssertEqual(commands(twice, event: "Stop"), ["/usr/local/bin/audit", "'quoted' path Stop"])
    }

    internal func testUninstallRemovesOnlyVSVibeEntries() {
        let installed = HookSettings.installing(
            into: ["hooks": ["Stop": [userHook]], "theme": "dark"],
            scriptPath: scriptPath,
            scriptCommand: scriptPath
        )

        let cleaned = HookSettings.uninstalling(from: installed, scriptPath: scriptPath)

        XCTAssertEqual(commands(cleaned, event: "Stop"), ["/usr/local/bin/audit"])
        XCTAssertNil((cleaned["hooks"] as? [String: Any])?["SessionStart"])
        XCTAssertEqual(cleaned["theme"] as? String, "dark")

        let empty = HookSettings.uninstalling(
            from: HookSettings.installing(into: [:], scriptPath: scriptPath, scriptCommand: scriptPath),
            scriptPath: scriptPath
        )
        XCTAssertNil(empty["hooks"])
        XCTAssertEqual(HookSettings.uninstalling(from: ["a": 1], scriptPath: scriptPath)["a"] as? Int, 1)
    }

    internal func testObjectParsing() throws {
        XCTAssertTrue(try HookSettings.object(from: Data()).isEmpty)
        XCTAssertTrue(try HookSettings.object(from: Data("[1]".utf8)).isEmpty)
        XCTAssertEqual(try HookSettings.object(from: Data(#"{"a":"b"}"#.utf8))["a"] as? String, "b")
        XCTAssertThrowsError(try HookSettings.object(from: Data("{oops".utf8)))

        let data = try HookSettings.data(of: ["b": 1, "a": 2])
        XCTAssertEqual(String(bytes: data, encoding: .utf8), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
    }

    internal func testRegisteredEventsWithoutHooks() {
        XCTAssertEqual(HookSettings.registeredEvents(inSettings: [:], scriptPath: scriptPath), [])
        XCTAssertEqual(HookSettings.registeredEvents(inSettings: ["hooks": "x"], scriptPath: scriptPath), [])
    }

    deinit {
        // Stateless tests.
    }
}
