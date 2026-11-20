import Foundation

/// `RemoteShellRunning` with a real process: runs `executableURL` (ssh) with
/// an argv array (no local shell), off the caller's thread and bounded by
/// `timeout` (then the process is killed and the result is an ssh failure).
/// stdin is read from a temporary file and stdout / stderr go to temporary
/// files rather than pipes, so a multiplexing master that ssh forks into the
/// background can never keep a read open, and a dead ssh can never cause a
/// broken-pipe write.
internal struct SSHCommandRunner: RemoteShellRunning {
    /// Upper bound for one call (connect, plus e.g. an interactive login shell).
    internal static let defaultTimeout: TimeInterval = 30

    private static let reapTimeout: TimeInterval = 1

    internal let executableURL: URL
    internal let timeout: TimeInterval
    /// Prepared (`RemoteSSH.prepareControlDirectory`) before each call; nil skips it.
    internal let controlDirectory: URL?

    internal init(
        executableURL: URL = RemoteSSH.executableURL,
        timeout: TimeInterval = defaultTimeout,
        controlDirectory: URL? = RemoteSSH.controlDirectory
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.controlDirectory = controlDirectory
    }

    internal func run(arguments: [String], input: Data?) async -> RemoteCommandResult {
        let runner = self
        return await Task.detached(priority: .utility) {
            runner.runBlocking(arguments: arguments, input: input)
        }
        .value
    }

    /// The blocking body of `run`.
    internal func runBlocking(arguments: [String], input: Data?) -> RemoteCommandResult {
        if let controlDirectory {
            try? RemoteSSH.prepareControlDirectory(at: controlDirectory)
        }
        let files = ProcessFiles()
        defer { files.remove() }
        guard let streams = files.open(input: input) else {
            return .sshFailure("Could not create temporary files for ssh.")
        }
        defer { streams.close() }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = streams.input
        process.standardOutput = streams.output
        process.standardError = streams.error

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .sshFailure("Could not start \(executableURL.path).")
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + Self.reapTimeout)
            return .sshFailure("ssh timed out.")
        }
        return RemoteCommandResult(
            status: process.terminationStatus,
            output: files.output(),
            errorOutput: String(bytes: files.errorOutput(), encoding: .utf8) ?? ""
        )
    }
}
