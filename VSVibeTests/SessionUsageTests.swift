@testable import VSVibe
import XCTest

internal final class SessionUsageTests: XCTestCase {
    internal func testEstimatedCostUsesLastModelRates() {
        var usage = SessionUsage()
        usage.totalInput = 1_000_000
        usage.totalOutput = 1_000_000
        usage.lastModel = "claude-sonnet-4-6"
        XCTAssertEqual(usage.estimatedCostUSD, 18.0, accuracy: 0.0001)

        usage.lastModel = "claude-haiku-4-5"
        XCTAssertEqual(usage.estimatedCostUSD, 6.0, accuracy: 0.0001)
    }

    internal func testContextPercentScalesAndCaps() {
        var usage = SessionUsage()
        XCTAssertEqual(usage.contextWindow, 200_000)
        XCTAssertEqual(usage.contextPercent, 0, accuracy: 0.0001)

        usage.lastContextTokens = 50_000
        XCTAssertEqual(usage.contextPercent, 25, accuracy: 0.0001)

        usage.lastContextTokens = 400_000
        XCTAssertEqual(usage.contextPercent, 100, accuracy: 0.0001)
    }

    deinit {
        // No shared state to release.
    }
}
