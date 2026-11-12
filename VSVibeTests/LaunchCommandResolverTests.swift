@testable import VSVibe
import XCTest

internal final class LaunchCommandResolverTests: XCTestCase {
    internal func testDefaultCommandDoesNotDependOnAncestors() {
        for path in ["/Users/x/work/xim/project", "/Users/x/work/XIM/project", "/"] {
            XCTAssertEqual(LaunchCommandResolver.defaultCommand(for: URL(fileURLWithPath: path)), "claude")
        }
    }

    internal func testDefaultCommandForOrdinaryFolder() {
        let url = URL(fileURLWithPath: "/Users/x/pet/demo")
        XCTAssertEqual(LaunchCommandResolver.defaultCommand(for: url), "claude")
    }

    internal func testAliasLookup() throws {
        XCTAssertNotNil(LaunchCommandResolver.alias(for: "claude")?.claudeConfigDir)
        XCTAssertNil(LaunchCommandResolver.alias(for: "opencode")?.claudeConfigDir)
        XCTAssertFalse(try XCTUnwrap(LaunchCommandResolver.alias(for: "opencode")).supportsClaudeHooks)
        XCTAssertNil(LaunchCommandResolver.alias(for: "not-a-real-alias"))
    }

    internal func testHookCapableAliasesExcludeOpencode() {
        let capable = LaunchCommandResolver.hookCapableAliases
        XCTAssertFalse(capable.contains { $0.command == "opencode" })
        XCTAssertTrue(capable.allSatisfy { $0.claudeConfigDir != nil })
        XCTAssertEqual(capable.map(\.command), ["claude"])
    }

    internal func testKnownAliasesContainOnlyBuiltInCLIs() {
        XCTAssertEqual(LaunchCommandResolver.knownAliases, ["claude", "opencode", "codex"])
    }

    internal func testBaseCommandStripsArguments() {
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "claude --continue"), "claude")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "claude"), "claude")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: "  claude-work --resume foo "), "claude-work")
        XCTAssertEqual(LaunchCommandResolver.baseCommand(of: ""), "")
    }

    internal func testBaseCommandResolvesAliasForCommandWithFlags() {
        let alias = LaunchCommandResolver.alias(for: LaunchCommandResolver.baseCommand(of: "claude --continue"))
        XCTAssertNotNil(alias?.claudeConfigDir)
        XCTAssertEqual(alias?.command, "claude")
    }

    internal func testContinueCommandAppendsFlag() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude"), "claude --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude-work"), "claude-work --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "  claude  "), "claude --continue")
    }

    internal func testContinueCommandIsIdempotent() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude --continue"), "claude --continue")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "claude -c"), "claude -c")
    }

    internal func testContinueCommandLeavesEmptyUnchanged() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: ""), "")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "   "), "")
    }

    deinit {
        // Nothing to release.
    }
}
