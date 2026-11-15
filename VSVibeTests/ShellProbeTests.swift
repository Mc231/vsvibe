@testable import VSVibe
import XCTest

internal final class ShellProbeTests: XCTestCase {
    private var directory = TestSupport.placeholderURL

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("probe")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testInteractiveLoginArguments() {
        XCTAssertEqual(ShellProbe.interactiveLoginArguments, ["-i", "-l", "-c"])
    }

    internal func testCapturesStdoutAndStatus() {
        let outcome = ShellProbe.run(
            shell: "/bin/sh",
            arguments: ["-c", "echo hello; echo oops >&2; exit 3"],
            captureOutput: true
        )
        XCTAssertEqual(outcome, .exited(status: 3, output: "hello\n"))
    }

    internal func testDiscardsStdoutUnlessCaptured() {
        XCTAssertEqual(
            ShellProbe.run(shell: "/bin/sh", arguments: ["-c", "echo hello"]),
            .exited(status: 0, output: "")
        )
    }

    internal func testStdinIsEmpty() {
        let outcome = ShellProbe.run(shell: "/bin/sh", arguments: ["-c", "cat; echo done"], captureOutput: true)
        XCTAssertEqual(outcome, .exited(status: 0, output: "done\n"))
    }

    internal func testTimeoutKillsTheShell() {
        let start = Date()
        let outcome = ShellProbe.run(shell: "/bin/sh", arguments: ["-c", "sleep 10"], timeout: 0.2)
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    internal func testBackgroundChildDoesNotBlockTheResult() {
        // An rc file that leaves a process holding stdout open must not hang the probe.
        let outcome = ShellProbe.run(
            shell: "/bin/sh",
            arguments: ["-c", "(sleep 10 &) ; echo ready"],
            timeout: 3,
            captureOutput: true
        )
        XCTAssertEqual(outcome, .exited(status: 0, output: "ready\n"))
    }

    internal func testMissingShellFailsToLaunch() {
        XCTAssertEqual(ShellProbe.run(shell: "/bin/not-a-shell", arguments: []), .failedToLaunch)
    }

    internal func testFakeShellRequiresInteractiveLoginArguments() {
        let shell = FakeShell.make(in: directory)
        XCTAssertEqual(ShellProbe.run(shell: shell, arguments: ["-c", "true"]), .exited(status: 99, output: ""))
        XCTAssertEqual(
            ShellProbe.run(shell: shell, arguments: ShellProbe.interactiveLoginArguments + ["true"]),
            .exited(status: 0, output: "")
        )
    }

    // MARK: - ShellCommandName

    internal func testCommandNameValidation() {
        for name in ["claude", "claude-work", "claude_2", "c.x", "A9"] {
            XCTAssertTrue(ShellCommandName.isValid(name), name)
            XCTAssertEqual(ShellCommandName.quoted(name), "'\(name)'")
        }
        for name in ["", "-x", ".", "..", "a b", "a'b", "a;b", "$(x)", "a/b", "~x", "a=b", "ä"] {
            XCTAssertFalse(ShellCommandName.isValid(name), name)
            XCTAssertNil(ShellCommandName.quoted(name), name)
        }
    }

    deinit {
        // The temp dir is removed in tearDown.
    }
}
