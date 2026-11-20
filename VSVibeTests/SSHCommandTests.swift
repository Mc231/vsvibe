@testable import VSVibe
import XCTest

/// The `ssh` line typed into a remote pane's local shell: its exact shape,
/// validation of hostile input, and (in `SSHCommandShellTests`) what real
/// shells make of it.
internal final class SSHCommandTests: XCTestCase {
    private let paneID = UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID()

    private func line(
        _ target: RemoteTarget,
        _ invocation: RemoteInvocation = .command("claude")
    ) -> Result<String, RemoteTargetError> {
        SSHCommand.line(for: target, paneID: paneID, invocation: invocation)
    }

    private func error(_ target: RemoteTarget, _ invocation: RemoteInvocation = .shell) -> RemoteTargetError? {
        guard case .failure(let error) = line(target, invocation) else {
            return nil
        }
        return error
    }

    // MARK: - Shape

    internal func testCommandLineWithHomeRelativeFolder() {
        let target = RemoteTarget(destination: "dev", remotePath: "~/proj")
        let script = #"exec env VSVIBE_PANE_ID=11111111-2222-3333-4444-555555555555 "$SHELL" "#
            + #"-i -l -c 'cd ~/'\''proj'\'' || exit 1; exec claude'"#
        XCTAssertEqual(SSHCommand.remoteScript(for: target, paneID: paneID, invocation: .command("claude")), script)
        XCTAssertEqual(line(target), .success("ssh -t -- 'dev' " + SSHCommand.shellQuoted(script)))
    }

    internal func testPortIsPassedBeforeTheDestination() throws {
        let target = RemoteTarget(destination: "me@10.0.0.2", port: 222, remotePath: "/srv/app")
        let built = try line(target).get()
        XCTAssertTrue(built.hasPrefix("ssh -t -p 222 -- 'me@10.0.0.2' "), built)
    }

    internal func testRemoteScriptForEachInvocation() {
        let target = RemoteTarget(destination: "dev", remotePath: "/srv/app")
        let shell = #"exec env VSVIBE_PANE_ID=11111111-2222-3333-4444-555555555555 "$SHELL""#
        XCTAssertEqual(
            SSHCommand.remoteScript(for: target, paneID: paneID, invocation: .shell),
            "cd '/srv/app' || exit 1; \(shell) -l"
        )
        XCTAssertEqual(
            SSHCommand.remoteScript(for: target, paneID: paneID, invocation: .command("claudework --model opus")),
            #"\#(shell) -i -l -c 'cd '\''/srv/app'\'' || exit 1; exec claudework --model opus'"#
        )
        XCTAssertEqual(
            SSHCommand.remoteScript(
                for: target,
                paneID: paneID,
                invocation: .resumeOrStart(command: "claude", claudeSessionID: "abc-1")
            ),
            #"\#(shell) -i -l -c 'cd '\''/srv/app'\'' || exit 1; "#
                + #"claude --resume abc-1 || exec claude --session-id abc-1'"#
        )
    }

    internal func testNoFolderStaysInTheRemoteHome() {
        let target = RemoteTarget(destination: "dev")
        XCTAssertEqual(
            SSHCommand.remoteScript(for: target, paneID: paneID, invocation: .shell),
            #"exec env VSVIBE_PANE_ID=11111111-2222-3333-4444-555555555555 "$SHELL" -l"#
        )
    }

    internal func testRemotePathQuotingKeepsTildeExpansion() {
        XCTAssertEqual(SSHCommand.quotedRemotePath("~"), "~")
        XCTAssertEqual(SSHCommand.quotedRemotePath("~/"), "~/")
        XCTAssertEqual(SSHCommand.quotedRemotePath("~/a b"), "~/'a b'")
        XCTAssertEqual(SSHCommand.quotedRemotePath("/srv/it's"), #"'/srv/it'\''s'"#)
        XCTAssertEqual(SSHCommand.quotedRemotePath("~bob/x"), "'~bob/x'")
        XCTAssertEqual(SSHCommand.quotedRemotePath("-rf"), "'./-rf'")
        XCTAssertEqual(SSHCommand.quotedRemotePath("rel/dir"), "'rel/dir'")
    }

    internal func testShellQuoting() {
        XCTAssertEqual(SSHCommand.shellQuoted(""), "''")
        XCTAssertEqual(SSHCommand.shellQuoted("a b"), "'a b'")
        XCTAssertEqual(SSHCommand.shellQuoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(SSHCommand.shellQuoted("$(x) `y` \"z\""), "'$(x) `y` \"z\"'")
    }

    // MARK: - Validation

    internal func testAcceptedDestinations() {
        for destination in ["dev", "me@host.example.com", "user_1@10.0.0.2", "fe80::1%en0", "a-b.c"] {
            XCTAssertNil(SSHCommand.validationError(ofDestination: destination), destination)
        }
    }

    internal func testRejectedDestinations() {
        XCTAssertEqual(SSHCommand.validationError(ofDestination: ""), .destinationEmpty)
        XCTAssertEqual(SSHCommand.validationError(ofDestination: "me@"), .destinationEmpty)
        XCTAssertEqual(SSHCommand.validationError(ofDestination: "-oProxyCommand=x"), .destinationStartsWithDash)
        XCTAssertEqual(
            SSHCommand.validationError(ofDestination: String(repeating: "a", count: 256)),
            .destinationTooLong
        )
        let hostile = ["a b", "a;b", "a'b", "a$(x)", "a`x`", "a\nb", "a|b", "a&b", "[::1]", "a/b", "a\u{0}b", "hôst"]
        for destination in hostile {
            XCTAssertEqual(
                SSHCommand.validationError(ofDestination: destination),
                .destinationHasInvalidCharacters,
                destination
            )
        }
    }

    internal func testPortRange() {
        XCTAssertNil(error(RemoteTarget(destination: "dev", port: 1)))
        XCTAssertNil(error(RemoteTarget(destination: "dev", port: 65_535)))
        XCTAssertEqual(error(RemoteTarget(destination: "dev", port: 0)), .portOutOfRange)
        XCTAssertEqual(error(RemoteTarget(destination: "dev", port: 65_536)), .portOutOfRange)
        XCTAssertEqual(error(RemoteTarget(destination: "dev", port: -22)), .portOutOfRange)
    }

    internal func testControlCharactersAreRejected() {
        XCTAssertEqual(error(RemoteTarget(destination: "dev", remotePath: "a\nrm -rf ~")), .pathHasControlCharacters)
        XCTAssertEqual(error(RemoteTarget(destination: "dev", command: "claude\nrm")), .commandHasControlCharacters)
        XCTAssertEqual(error(RemoteTarget(destination: "dev"), .command("a\rb")), .commandHasControlCharacters)
        XCTAssertEqual(
            error(RemoteTarget(destination: "dev"), .resumeOrStart(command: "a\tb", claudeSessionID: "id")),
            .commandHasControlCharacters
        )
    }

    internal func testResumeNeedsAValidConversationID() {
        XCTAssertEqual(
            error(RemoteTarget(destination: "dev"), .resumeOrStart(command: "claude", claudeSessionID: "a;b")),
            .invalidClaudeSessionID
        )
        XCTAssertNil(error(RemoteTarget(destination: "dev"), .resumeOrStart(command: "claude", claudeSessionID: "a-b")))
    }

    internal func testEveryErrorHasAMessage() {
        let errors: [RemoteTargetError] = [
            .commandHasControlCharacters, .destinationEmpty, .destinationHasInvalidCharacters,
            .destinationStartsWithDash, .destinationTooLong, .invalidClaudeSessionID,
            .pathHasControlCharacters, .portNotANumber, .portOutOfRange
        ]
        XCTAssertEqual(Set(errors.map(\.message)).count, errors.count)
        XCTAssertTrue(errors.allSatisfy { $0.message.hasSuffix(".") })
    }

    deinit {
        // Nothing to release.
    }
}
