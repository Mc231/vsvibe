import Foundation

/// Polling helper for tests that observe work finishing on the main actor
/// after a timer, a dispatch hop or a detached task.
@MainActor
internal enum AsyncWait {
    private static let step: UInt64 = 20_000_000
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// Polls `condition` on the main actor until it holds or `timeout` elapses.
    /// Returns the final value of `condition`.
    @discardableResult
    internal static func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                return false
            }
            try? await Task.sleep(nanoseconds: step)
        }
        return true
    }

    /// Lets queued main-queue work (e.g. `asyncAfter(0)`) and tasks run.
    internal static func drainMainQueue(seconds: TimeInterval = 0.1) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * nanosecondsPerSecond))
    }
}
