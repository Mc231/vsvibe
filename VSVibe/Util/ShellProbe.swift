import Foundation

/// Runs a short script in the user's shell and reports how it ended. Used to
/// ask the user's interactive login shell about commands, since aliases and
/// functions from `~/.zshrc` only exist in an interactive shell.
///
/// Interactive rc files can be slow or block (prompts, network, job control
/// without a terminal), so every run is bounded by a timeout: on expiry the
/// shell is killed and the outcome is `.timedOut`. stdin is `/dev/null` and
/// stderr is discarded; stdout goes to a temporary file (not a pipe), so a
/// background process started by an rc file can never keep the read open.
/// Blocking: call off the main thread.
internal enum ShellProbe {
    internal enum Outcome: Equatable {
        case exited(status: Int32, output: String)
        case failedToLaunch
        case timedOut
    }

    /// Default upper bound for one probe.
    internal static let defaultTimeout: TimeInterval = 5
    /// `<shell> -i -l -c <script>`: an interactive login shell, so both the
    /// login files and the interactive rc files (`~/.zshrc`, `~/.bashrc`) run.
    internal static let interactiveLoginArguments = ["-i", "-l", "-c"]

    private static let reapTimeout: TimeInterval = 1

    /// Runs `shell` with `arguments`. `captureOutput` keeps stdout (returned in
    /// `.exited`); otherwise it is discarded and `output` is empty.
    internal static func run(
        shell: String,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout,
        captureOutput: Bool = false
    ) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let outputURL = captureOutput ? makeOutputFile() : nil
        let outputHandle = outputURL.flatMap { try? FileHandle(forWritingTo: $0) }
        process.standardOutput = outputHandle ?? FileHandle.nullDevice
        defer {
            try? outputHandle?.close()
            if let outputURL {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failedToLaunch
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            // SIGKILL also ends a shell stopped by job control (SIGTTOU/SIGTTIN).
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + reapTimeout)
            return .timedOut
        }
        let output = outputURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return .exited(status: process.terminationStatus, output: output)
    }

    private static func makeOutputFile() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vsvibe-probe-\(UUID().uuidString).out")
        return FileManager.default.createFile(atPath: url.path, contents: nil) ? url : nil
    }
}
