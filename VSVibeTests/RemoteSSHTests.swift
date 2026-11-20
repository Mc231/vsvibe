@testable import VSVibe
import XCTest

/// Background ssh argument lists, connections, results and reconnect backoff.
internal final class RemoteSSHTests: XCTestCase {
    private let multiplexing = [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "ControlMaster=auto",
        "-o", "ControlPath=~/.vsvibe/ssh/cm-%C",
        "-o", "ControlPersist=60"
    ]

    internal func testCommandArgumentsWrapTheScriptInSh() throws {
        let connection = try XCTUnwrap(SSHConnection(target: RemoteTarget(destination: "me@dev", port: 2_222)))

        let arguments = RemoteSSH.commandArguments(for: connection, script: "echo 'hi'")

        XCTAssertEqual(
            arguments,
            multiplexing + ["-p", "2222", "--", "me@dev", #"exec /bin/sh -c 'echo '\''hi'\'''"#]
        )
        XCTAssertEqual(FakeRemoteRunner.innerScript(of: arguments), "echo 'hi'")
    }

    internal func testStreamArgumentsAddKeepAlives() throws {
        let connection = try XCTUnwrap(SSHConnection(target: RemoteTarget(destination: "dev")))

        let arguments = RemoteSSH.streamArguments(for: connection, script: "true")

        XCTAssertEqual(
            arguments,
            multiplexing + [
                "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
                "--", "dev", "exec /bin/sh -c 'true'"
            ]
        )
    }

    internal func testConnectionRejectsInvalidTargets() {
        XCTAssertNil(SSHConnection(target: RemoteTarget(destination: "-oProxyCommand=x")))
        XCTAssertNil(SSHConnection(target: RemoteTarget(destination: "dev", port: 0)))
        XCTAssertNil(SSHConnection(target: RemoteTarget(destination: "dev", remotePath: "a\nb")))
        XCTAssertEqual(
            SSHConnection(target: RemoteTarget(destination: "dev", remotePath: "/a")),
            SSHConnection(target: RemoteTarget(destination: "dev", remotePath: "/b", command: "htop"))
        )
    }

    internal func testControlDirectoryIsPrivate() throws {
        let base = TestSupport.makeTempDir("ssh-control")
        defer { TestSupport.remove(base) }
        let directory = base.appendingPathComponent("nested/ssh", isDirectory: true)

        try RemoteSSH.prepareControlDirectory(at: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try RemoteSSH.prepareControlDirectory(at: directory)

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
        XCTAssertEqual(RemoteSSH.controlDirectory.lastPathComponent, "ssh")
        XCTAssertEqual(RemoteSSH.executableURL.path, "/usr/bin/ssh")
    }

    internal func testResultHelpers() {
        let failure = RemoteCommandResult(status: 255, errorOutput: "warning\nPermission denied (publickey).\n\n")
        XCTAssertTrue(failure.isSSHFailure)
        XCTAssertEqual(failure.errorSummary, "Permission denied (publickey).")

        let quiet = RemoteCommandResult(status: 2, output: Data("main\n".utf8))
        XCTAssertFalse(quiet.isSSHFailure)
        XCTAssertEqual(quiet.errorSummary, "exit status 2")
        XCTAssertEqual(quiet.outputText, "main\n")
        XCTAssertEqual(RemoteCommandResult(status: 0, output: Data([0xFF])).outputText, "")
        XCTAssertEqual(RemoteCommandResult.sshFailure("down").errorSummary, "down")
    }

    internal func testBackoffDoublesUpToTheCap() {
        let backoff = ReconnectBackoff()
        XCTAssertEqual(backoff.delay(afterFailures: 0), 0)
        XCTAssertEqual((1...8).map { backoff.delay(afterFailures: $0) }, [1, 2, 4, 8, 16, 32, 60, 60])
        XCTAssertEqual(backoff.delay(afterFailures: 10_000), 60)

        let custom = ReconnectBackoff(initialDelay: 0.5, maximumDelay: 3, stableDuration: 10)
        XCTAssertEqual((1...4).map { custom.delay(afterFailures: $0) }, [0.5, 1, 2, 3])
    }

    internal func testStableConnectionsResetTheFailureCount() {
        let backoff = ReconnectBackoff()
        XCTAssertEqual(backoff.failures(after: 0, connectedFor: 0), 1)
        XCTAssertEqual(backoff.failures(after: 4, connectedFor: 5), 5)
        XCTAssertEqual(backoff.failures(after: 4, connectedFor: 30), 1)
    }

    deinit {
        // Stateless tests.
    }
}
