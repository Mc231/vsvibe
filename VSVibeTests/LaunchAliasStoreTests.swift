@testable import VSVibe
import XCTest

@MainActor
internal final class LaunchAliasStoreTests: XCTestCase {
    private var directory = TestSupport.placeholderURL

    private var fileURL: URL {
        directory.appendingPathComponent("aliases.json")
    }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("aliases")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testFreshStoreHasOnlyBuiltIns() {
        let store = LaunchAliasStore(fileURL: fileURL)
        XCTAssertTrue(store.customAliases.isEmpty)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.aliases, LaunchCommandResolver.aliases)
        XCTAssertNil(store.alias(for: "unknown"))
    }

    internal func testSaveNormalizesAndPersistsCustomAlias() throws {
        let store = LaunchAliasStore(fileURL: fileURL)
        try store.save(command: "  claude-work \n", configPath: " ~/.claude-work ")
        let alias = try XCTUnwrap(store.alias(for: "claude-work --continue"))
        XCTAssertEqual(alias.id, "claude-work")
        XCTAssertTrue(alias.supportsClaudeHooks)
        XCTAssertEqual(alias.claudeConfigDir?.path, NSHomeDirectory() + "/.claude-work")
        XCTAssertEqual(alias.settingsURL?.lastPathComponent, "settings.json")
        XCTAssertEqual(LaunchAliasStore(fileURL: fileURL).customAliases, [alias])
        XCTAssertEqual(store.aliases.count, LaunchCommandResolver.aliases.count + 1)
    }

    internal func testEditRenameAndRemovePersistWithoutReseeding() throws {
        let store = LaunchAliasStore(fileURL: fileURL)
        try store.save(command: "work", configPath: "/tmp/first")
        try store.save(command: "other", configPath: "")
        try store.save(command: "work", configPath: "/tmp/second", replacing: "work")
        XCTAssertEqual(store.alias(for: "work")?.claudeConfigDir?.path, "/tmp/second")
        try store.save(command: "renamed", configPath: "", replacing: "work")
        XCTAssertEqual(store.customAliases.map(\.command), ["renamed", "other"])
        XCTAssertNil(store.alias(for: "work"))
        XCTAssertNil(store.alias(for: "renamed")?.settingsURL)
        XCTAssertFalse(try XCTUnwrap(store.alias(for: "renamed")).supportsClaudeHooks)
        try store.remove(command: "renamed")
        try store.remove(command: "other")
        XCTAssertTrue(LaunchAliasStore(fileURL: fileURL).customAliases.isEmpty)
    }

    internal func testInvalidAndDuplicateEditsLeaveStateAndFileUnchanged() throws {
        let store = LaunchAliasStore(fileURL: fileURL)
        try store.save(command: "work", configPath: "/tmp/config")
        try store.save(command: "other", configPath: "")
        let before = try Data(contentsOf: fileURL)
        for name in ["", " \n", "work --continue", "bad;command", "-flag", ".", "..", "bad\tname"] {
            XCTAssertThrowsError(try store.save(command: name, configPath: ""))
        }
        for name in LaunchCommandResolver.knownAliases {
            XCTAssertThrowsError(try store.save(command: name, configPath: ""))
        }
        XCTAssertThrowsError(try store.save(command: "work", configPath: ""))
        XCTAssertThrowsError(try store.save(command: "work", configPath: "", replacing: "other"))
        XCTAssertThrowsError(try store.save(command: "new", configPath: "", replacing: "missing"))
        XCTAssertThrowsError(try store.remove(command: "claude"))
        for path in ["relative/config", "/tmp/bad\npath", "/tmp/bad\0path"] {
            XCTAssertThrowsError(try store.save(command: "new", configPath: path))
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
        XCTAssertEqual(store.customAliases.map(\.command), ["work", "other"])
    }

    internal func testLoadErrorsPreserveOriginalData() throws {
        let duplicate = LaunchAlias(command: "work", claudeConfigDir: nil)
        let invalid = LaunchAlias(command: "claude", claudeConfigDir: nil)
        let payloads = [
            Data("invalid json".utf8),
            try JSONEncoder().encode([duplicate, duplicate]),
            try JSONEncoder().encode([invalid])
        ]
        for data in payloads {
            try data.write(to: fileURL)
            let store = LaunchAliasStore(fileURL: fileURL)
            XCTAssertNotNil(store.loadError)
            XCTAssertTrue(store.customAliases.isEmpty)
            XCTAssertThrowsError(try store.save(command: "new", configPath: ""))
            XCTAssertEqual(try Data(contentsOf: fileURL), data)
        }
    }

    internal func testPersistenceFailureDoesNotChangeMemory() throws {
        let store = LaunchAliasStore(fileURL: fileURL)
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.save(command: "work", configPath: ""))
        XCTAssertTrue(store.customAliases.isEmpty)
    }

    internal func testCreatesParentDirectory() throws {
        let nested = directory.appendingPathComponent("nested/aliases.json")
        let store = LaunchAliasStore(fileURL: nested)
        try store.save(command: "work", configPath: "")
        XCTAssertEqual(LaunchAliasStore(fileURL: nested).customAliases.map(\.command), ["work"])
    }

    internal func testErrorsHaveActionableMessages() {
        let errors: [LaunchAliasStore.AliasError] = [
            .invalidCommand,
            .builtInCommand,
            .duplicateCommand,
            .invalidConfigPath,
            .missingAlias,
            .unreadableFile
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    internal func testHookStatusUsesRegisteredCustomAliases() throws {
        let store = LaunchAliasStore(fileURL: fileURL)
        try store.save(command: "work", configPath: directory.path)
        try store.save(command: "other", configPath: "")
        let settings = directory.appendingPathComponent("settings.json")
        let hook: [String: Any] = ["hooks": [["_id": HookInstaller.hookCommandIdentifier]]]
        try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [hook], "Notification": [hook]]])
            .write(to: settings)
        let status = HookInstaller.currentStatus(aliases: store.customAliases)
        XCTAssertEqual(status.aliases.map(\.alias.command), ["work"])
        XCTAssertTrue(try XCTUnwrap(status.aliases.first).isInstalled)
        XCTAssertEqual(HookInstaller.unsupportedAliases(in: store.customAliases).map(\.command), ["other"])
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
