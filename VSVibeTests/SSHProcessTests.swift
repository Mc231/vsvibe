@testable import VSVibe
import XCTest

/// The real process glue, run against `/bin/sh` instead of ssh.
@MainActor
internal final class SSHProcessTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")
    private var directory = TestSupport.placeholderURL

    private var controlDirectory: URL {
        directory.appendingPathComponent("control", isDirectory: true)
    }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("ssh-process")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testRunnerFeedsStdinAndCapturesBothOutputs() async {
        let runner = SSHCommandRunner(executableURL: shell, controlDirectory: controlDirectory)

        let result = await runner.run(
            arguments: ["-c", "cat; echo oops >&2; exit 3"],
            input: Data("hello\n".utf8)
        )

        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.outputText, "hello\n")
        XCTAssertEqual(result.errorOutput, "oops\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: controlDirectory.path))
    }

    internal func testRunnerWithoutInputReadsNothing() async {
        let runner = SSHCommandRunner(executableURL: shell, controlDirectory: nil)

        let result = await runner.run(arguments: ["-c", "cat; printf done"], input: nil)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.outputText, "done")
    }

    internal func testRunnerTimesOut() async {
        let runner = SSHCommandRunner(executableURL: shell, timeout: 0.2, controlDirectory: nil)

        let result = await runner.run(arguments: ["-c", "sleep 5"], input: nil)

        XCTAssertTrue(result.isSSHFailure)
        XCTAssertEqual(result.errorSummary, "ssh timed out.")
    }

    internal func testRunnerReportsAMissingExecutable() async {
        let missing = directory.appendingPathComponent("no-ssh")
        let runner = SSHCommandRunner(executableURL: missing, controlDirectory: nil)

        let result = await runner.run(arguments: [], input: Data("x".utf8))

        XCTAssertTrue(result.isSSHFailure)
        XCTAssertEqual(result.errorSummary, "Could not start \(missing.path).")
        XCTAssertEqual(SSHCommandRunner().executableURL, RemoteSSH.executableURL)
    }

    internal func testProcessFilesFailWithoutADirectory() {
        let files = ProcessFiles(directory: directory.appendingPathComponent("missing", isDirectory: true))
        XCTAssertNil(files.open(input: nil))
        XCTAssertEqual(files.output(), Data())
        XCTAssertEqual(files.errorOutput(), Data())
        files.remove()
    }

    internal func testStreamDeliversOutputThenExit() async {
        let launcher = SSHStreamLauncher(executableURL: shell, controlDirectory: controlDirectory)
        var output = ""
        var exits = 0

        _ = launcher.launch(
            arguments: ["-c", "printf 'one\\n'; sleep 0.1; printf 'two\\n'"],
            onOutput: { output += String(bytes: $0, encoding: .utf8) ?? "" },
            onExit: { exits += 1 }
        )

        let exited = await AsyncWait.until { exits == 1 }
        XCTAssertTrue(exited)
        _ = await AsyncWait.until(timeout: 1) { output == "one\ntwo\n" }
        XCTAssertEqual(output, "one\ntwo\n")
        XCTAssertEqual(exits, 1)
    }

    internal func testTerminatedStreamDropsOutputAndStillExits() async {
        let launcher = SSHStreamLauncher(executableURL: shell, controlDirectory: nil)
        var output = Data()
        var exits = 0

        let handle = launcher.launch(
            arguments: ["-c", "sleep 0.3; printf late; sleep 10"],
            onOutput: { output += $0 },
            onExit: { exits += 1 }
        )
        handle.terminate()
        handle.terminate()

        let exited = await AsyncWait.until { exits == 1 }
        XCTAssertTrue(exited)
        XCTAssertEqual(output, Data())
    }

    internal func testStreamThatCannotStartExits() async {
        let launcher = SSHStreamLauncher(executableURL: directory.appendingPathComponent("none"), controlDirectory: nil)
        var exits = 0

        let handle = launcher.launch(arguments: [], onOutput: { _ in XCTFail("no output") }, onExit: { exits += 1 })
        handle.terminate()

        let exited = await AsyncWait.until { exits == 1 }
        XCTAssertTrue(exited)
        XCTAssertEqual(SSHStreamLauncher().executableURL, RemoteSSH.executableURL)
    }

    deinit {
        // Stateless tests.
    }
}
