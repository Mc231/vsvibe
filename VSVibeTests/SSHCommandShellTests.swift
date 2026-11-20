@testable import VSVibe
import XCTest

/// Runs `SSHCommand` output through real shells: the typed line through the
/// local shell (with `ssh` stubbed to record its arguments), then the remote
/// script through a login shell standing in for the remote host, with a
/// folder name full of shell metacharacters.
internal final class SSHCommandShellTests: XCTestCase {
    private static let shells = ["/bin/sh", "/bin/zsh"]
    private static let hostileFolder = #"it's "odd" $(touch PWNED) `touch PWNED2` dir"#

    private var home = TestSupport.placeholderURL
    private let paneID = UUID()

    override internal func setUp() {
        super.setUp()
        home = TestSupport.makeTempDir("ssh-home")
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent(Self.hostileFolder, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override internal func tearDown() {
        TestSupport.remove(home)
        super.tearDown()
    }

    /// Runs `shell -c script` in `home` with a minimal environment; returns stdout.
    private func run(_ shell: String, _ arguments: [String], shellVariable: String = "/bin/sh") -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.currentDirectoryURL = home
        process.environment = ["HOME": home.path, "SHELL": shellVariable, "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            XCTFail("could not run \(shell): \(error)")
            return ""
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func target(command: String = "claude") -> RemoteTarget {
        RemoteTarget(destination: "me@dev", port: 222, remotePath: "~/" + Self.hostileFolder, command: command)
    }

    /// The folder's physical path, as `pwd -P` prints it (Foundation's
    /// `resolvingSymlinksInPath` maps `/private/var` back to `/var`).
    private func resolvedFolder() -> String {
        let path = home.appendingPathComponent(Self.hostileFolder).path
        guard let resolved = realpath(path, nil) else {
            return path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    internal func testLocalShellsPassTheScriptToSSHAsOneArgument() throws {
        let invocation = RemoteInvocation.command("claude --session-id abc")
        let line = try SSHCommand.line(for: target(), paneID: paneID, invocation: invocation).get()
        let script = SSHCommand.remoteScript(for: target(), paneID: paneID, invocation: invocation)
        for shell in Self.shells {
            let output = run(shell, ["-c", #"ssh() { for arg in "$@"; do printf '%s\n' "$arg"; done; }; "# + line])
            XCTAssertEqual(output, ["-t", "-p", "222", "--", "me@dev", script].joined(separator: "\n") + "\n", shell)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("PWNED").path))
    }

    internal func testRemoteScriptRunsTheCommandInTheFolderWithThePaneID() {
        let command = #"sh -c 'printf "%s|%s" "$VSVIBE_PANE_ID" "$(pwd -P)"'"#
        let script = SSHCommand.remoteScript(
            for: target(command: command),
            paneID: paneID,
            invocation: .command(command)
        )
        for shell in Self.shells {
            let output = run(shell, ["-c", script], shellVariable: shell)
            XCTAssertEqual(output, "\(paneID.uuidString)|\(resolvedFolder())", shell)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("PWNED").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("PWNED2").path))
    }

    internal func testResumeFallsBackToStartingTheConversation() {
        // Fails for `--resume` (like a conversation that never started), succeeds for `--session-id`.
        let command = #"sh -c 'test "$0" = --session-id && printf "started %s" "$1"'"#
        let invocation = RemoteInvocation.resumeOrStart(command: command, claudeSessionID: "abc-1")
        let script = SSHCommand.remoteScript(for: target(command: command), paneID: paneID, invocation: invocation)
        for shell in Self.shells {
            XCTAssertEqual(run(shell, ["-c", script], shellVariable: shell), "started abc-1", shell)
        }
    }

    internal func testMissingFolderExitsInsteadOfRunningElsewhere() {
        let missing = RemoteTarget(destination: "dev", remotePath: "/nonexistent/vsvibe", command: "pwd")
        let script = SSHCommand.remoteScript(for: missing, paneID: paneID, invocation: .command("pwd"))
        XCTAssertEqual(run("/bin/sh", ["-c", script]), "")
    }

    internal func testEmptyCommandStartsALoginShellInTheFolder() {
        let shellTarget = RemoteTarget(destination: "dev", remotePath: "~/" + Self.hostileFolder, command: "")
        let script = SSHCommand.remoteScript(for: shellTarget, paneID: paneID, invocation: .shell)
        // The stand-in login shell reads its commands from stdin: none, so it just exits.
        let output = run("/bin/sh", ["-c", script.replacingOccurrences(of: "\"$SHELL\" -l", with: "/bin/pwd -P")])
        XCTAssertEqual(output, resolvedFolder() + "\n")
    }

    deinit {
        // Nothing to release.
    }
}
