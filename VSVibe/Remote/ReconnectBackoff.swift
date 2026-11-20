import Foundation

/// When a remote stream reconnects after its ssh process ended: capped
/// exponential backoff over consecutive failures (1 s, 2 s, 4 s … 60 s by
/// default). A connection that stayed up for `stableDuration` was healthy, so
/// its end starts the count over.
internal struct ReconnectBackoff: Equatable, Sendable {
    /// Each failure doubles the delay, up to `maximumDelay`.
    private static let growthFactor = 2.0
    /// Bounds the exponent so the power stays finite.
    private static let maxDoublings = 32

    internal var initialDelay: TimeInterval = 1
    internal var maximumDelay: TimeInterval = 60
    internal var stableDuration: TimeInterval = 30

    /// The consecutive-failure count after a connection that lasted
    /// `connectedFor` seconds ended, following `previous` failures.
    internal func failures(after previous: Int, connectedFor: TimeInterval) -> Int {
        connectedFor >= stableDuration ? 1 : previous + 1
    }

    /// Seconds to wait before the next attempt after `failures` consecutive
    /// failures (0 for none).
    internal func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else {
            return 0
        }
        let doublings = Double(min(failures - 1, Self.maxDoublings))
        return min(maximumDelay, initialDelay * pow(Self.growthFactor, doublings))
    }
}
