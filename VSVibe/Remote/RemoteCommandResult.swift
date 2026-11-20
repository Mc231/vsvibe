import Foundation

/// How a one-shot remote call (`RemoteShellRunning`) ended.
internal struct RemoteCommandResult: Equatable, Sendable {
    /// ssh's own exit status for a failure to connect, authenticate or run
    /// (the remote command's status otherwise).
    internal static let sshFailureStatus: Int32 = 255

    internal let status: Int32
    internal let output: Data
    internal let errorOutput: String

    /// stdout as UTF-8 text (empty when it is not valid UTF-8).
    internal var outputText: String {
        String(bytes: output, encoding: .utf8) ?? ""
    }

    /// ssh itself failed: the host is unreachable, refused the key, timed out…
    internal var isSSHFailure: Bool {
        status == Self.sshFailureStatus
    }

    /// The last non-empty stderr line, for a status message.
    internal var errorSummary: String {
        errorOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? "exit status \(status)"
    }

    internal init(status: Int32, output: Data = Data(), errorOutput: String = "") {
        self.status = status
        self.output = output
        self.errorOutput = errorOutput
    }

    /// ssh could not run at all (e.g. failed to launch or timed out).
    internal static func sshFailure(_ message: String) -> Self {
        Self(status: sshFailureStatus, errorOutput: message)
    }
}
