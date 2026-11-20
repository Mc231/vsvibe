@testable import VSVibe
import XCTest

internal final class RemoteLaunchTests: XCTestCase {
    private let newID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
    private let newIDString = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    private func plan(
        _ target: RemoteTarget,
        override: String? = nil,
        resume: String? = nil
    ) -> RemoteLaunch.Plan {
        RemoteLaunch.plan(
            for: target,
            newClaudeSessionID: newID,
            commandOverride: override,
            resumeClaudeSessionID: resume
        )
    }

    internal func testFreshClaudePaneStartsWithAChosenID() {
        let result = plan(RemoteTarget(destination: "dev", command: "claudework --model opus"))
        XCTAssertEqual(result.invocation, .command("claudework --model opus --session-id \(newIDString)"))
        XCTAssertEqual(result.claudeSessionID, newIDString)
    }

    internal func testEmptyCommandIsAShell() {
        let result = plan(RemoteTarget(destination: "dev", command: "  "))
        XCTAssertEqual(result, RemoteLaunch.Plan(invocation: .shell, claudeSessionID: nil))
    }

    internal func testNonClaudeCommandRunsAsTyped() {
        let target = RemoteTarget(destination: "dev", command: "htop", runsClaude: false)
        XCTAssertEqual(plan(target), RemoteLaunch.Plan(invocation: .command("htop"), claudeSessionID: nil))
        XCTAssertEqual(
            plan(target, resume: "conv"),
            RemoteLaunch.Plan(invocation: .command("htop"), claudeSessionID: nil),
            "no resume for a command that doesn't run Claude"
        )
    }

    internal func testCommandPickingItsOwnConversationGetsNoID() {
        let target = RemoteTarget(destination: "dev")
        XCTAssertEqual(
            plan(target, override: "claude --continue"),
            RemoteLaunch.Plan(invocation: .command("claude --continue"), claudeSessionID: nil)
        )
        XCTAssertNil(plan(RemoteTarget(destination: "dev", command: "claude --session-id=fixed")).claudeSessionID)
    }

    internal func testRestoreResumesOrStartsTheSavedConversation() {
        let target = RemoteTarget(destination: "dev", command: "claude --continue --model opus")
        XCTAssertEqual(
            plan(target, resume: "conv-1"),
            RemoteLaunch.Plan(
                invocation: .resumeOrStart(command: "claude --model opus", claudeSessionID: "conv-1"),
                claudeSessionID: "conv-1"
            )
        )
    }

    internal func testInvalidSavedIDStartsFresh() {
        let result = plan(RemoteTarget(destination: "dev"), resume: "bad id;rm")
        XCTAssertEqual(result.invocation, .command("claude --session-id \(newIDString)"))
    }

    internal func testResumeWithOnlyFlagsRunsTheCommand() {
        let result = plan(RemoteTarget(destination: "dev"), override: "--continue", resume: "conv")
        XCTAssertEqual(result, RemoteLaunch.Plan(invocation: .command("--continue"), claudeSessionID: nil))
    }

    internal func testConversationFlagHelpers() {
        XCTAssertTrue(LaunchCommandResolver.hasConversationFlag("claude -c"))
        XCTAssertTrue(LaunchCommandResolver.hasConversationFlag("claude --resume=x"))
        XCTAssertTrue(LaunchCommandResolver.hasConversationFlag("claude -r x"))
        XCTAssertTrue(LaunchCommandResolver.hasConversationFlag("claude --session-id x"))
        XCTAssertFalse(LaunchCommandResolver.hasConversationFlag("claude --model opus"))
        XCTAssertEqual(
            LaunchCommandResolver.withoutConversationFlags("claude --session-id x --model opus --resume=y -c"),
            "claude --model opus"
        )
    }

    deinit {
        // Nothing to release.
    }
}
