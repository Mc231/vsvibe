import Foundation

/// What remote pane monitoring runs ssh with, and its timing. `live` uses
/// `/usr/bin/ssh`; tests inject fakes and an instant `sleep`.
@MainActor
internal struct RemoteServices {
    /// Waits the given seconds (returns early when the task is cancelled).
    internal typealias Sleep = @Sendable (TimeInterval) async -> Void

    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// The real ssh client and clock.
    internal static var live: Self {
        Self(runner: SSHCommandRunner(), launcher: SSHStreamLauncher())
    }

    /// One-shot calls (git branch, hook install).
    internal var runner: any RemoteShellRunning
    /// Long-running streams (events, transcripts).
    internal var launcher: any RemoteProcessLaunching
    internal var backoff = ReconnectBackoff()
    internal var sleep: Sleep = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * nanosecondsPerSecond))
    }
    internal var now: () -> Date = { Date() }
    /// How often a remote pane's git branch is re-read.
    internal var branchPollInterval: TimeInterval = 20
}
