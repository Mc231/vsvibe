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

    internal func testResumeCommandAppendsSessionID() {
        XCTAssertEqual(LaunchCommandResolver.resumeCommand(for: "claude", claudeSessionID: "s1"), "claude --resume s1")
        XCTAssertEqual(
            LaunchCommandResolver.resumeCommand(for: "  work --model opus ", claudeSessionID: "s1"),
            "work --model opus --resume s1"
        )
    }

    internal func testResumeCommandReplacesConversationFlags() {
        let cases = [
            "claude --continue": "claude --resume new",
            "claude -c --verbose": "claude --verbose --resume new",
            "claude --resume old": "claude --resume new",
            "claude -r old --verbose": "claude --verbose --resume new",
            "claude --resume=old": "claude --resume new",
            "claude -r --verbose": "claude --verbose --resume new",
            "claude --resume": "claude --resume new"
        ]
        for (command, expected) in cases {
            XCTAssertEqual(LaunchCommandResolver.resumeCommand(for: command, claudeSessionID: "new"), expected, command)
        }
    }

    internal func testValidClaudeSessionIDs() {
        XCTAssertTrue(LaunchCommandResolver.isValidClaudeSessionID("0b9c1f2e-4a5d-4e3b-9f00-123456789abc"))
        XCTAssertTrue(LaunchCommandResolver.isValidClaudeSessionID("abc_DEF-123"))
        for invalid in ["", "a b", "x;rm -rf ~", "$(id)", "a\nb", "ü", String(repeating: "a", count: 129)] {
            XCTAssertFalse(LaunchCommandResolver.isValidClaudeSessionID(invalid), invalid)
        }
    }

    internal func testContinueCommandLeavesEmptyUnchanged() {
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: ""), "")
        XCTAssertEqual(LaunchCommandResolver.continueCommand(for: "   "), "")
    }

    deinit {
        // Nothing to release.
    }
}
