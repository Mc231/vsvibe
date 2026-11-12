@testable import VSVibe
import XCTest

/// `LaunchAliasStore.expandingTilde(in:)` must match `NSString.expandingTildeInPath`.
@MainActor
internal final class LaunchAliasTildeTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("tilde")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testPathsWithoutTildeAreUnchanged() {
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: "/opt/claude"), "/opt/claude")
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: "relative/path"), "relative/path")
    }

    internal func testCurrentUserTildeExpandsToHome() {
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: "~"), NSHomeDirectory())
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: "~/.claude-work"), NSHomeDirectory() + "/.claude-work")
    }

    internal func testNamedUserTildeExpandsToThatUsersHome() {
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: "~root/cfg"), "/var/root/cfg")
    }

    internal func testUnknownUserLeavesPathUnchanged() {
        let path = "~no-such-user-vsvibe/cfg"
        XCTAssertEqual(LaunchAliasStore.expandingTilde(in: path), path)
    }

    internal func testSaveExpandsTildeConfigPath() throws {
        let store = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        try store.save(command: "work", configPath: "~/.claude-work")
        let expected = URL(fileURLWithPath: NSHomeDirectory() + "/.claude-work", isDirectory: true).standardizedFileURL
        XCTAssertEqual(store.customAliases.first?.claudeConfigDir, expected)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
