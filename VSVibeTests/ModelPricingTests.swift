@testable import VSVibe
import XCTest

final class ModelPricingTests: XCTestCase {
    func testExactRates() {
        let opus = ModelPricing.rates(for: "claude-opus-4-7")
        XCTAssertEqual(opus.input, 15.0)
        XCTAssertEqual(opus.output, 75.0)

        let sonnet = ModelPricing.rates(for: "claude-sonnet-4-6")
        XCTAssertEqual(sonnet.input, 3.0)
        XCTAssertEqual(sonnet.output, 15.0)

        let haiku = ModelPricing.rates(for: "claude-haiku-4-5")
        XCTAssertEqual(haiku.input, 1.0)
        XCTAssertEqual(haiku.output, 5.0)
    }

    func testFamilyHeuristicFallback() {
        // Unknown exact key but recognizable family.
        XCTAssertEqual(ModelPricing.rates(for: "claude-sonnet-9-9").input, 3.0)
        XCTAssertEqual(ModelPricing.rates(for: "something-opus-x").input, 15.0)
        XCTAssertEqual(ModelPricing.rates(for: "claude-3-5-haiku").input, 1.0)
    }

    func testUnknownAndNilFallBackToOpus() {
        XCTAssertEqual(ModelPricing.rates(for: "gpt-4").input, 15.0)
        XCTAssertEqual(ModelPricing.rates(for: nil).input, 15.0)
    }

    func testCostComputation() {
        var usage = SessionUsage()
        usage.totalInput = 1_000_000      // $15 at opus
        usage.totalOutput = 1_000_000     // $75
        usage.totalCacheCreation = 1_000_000 // $18.75
        usage.totalCacheRead = 1_000_000  // $1.50
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-4-7", usage: usage), 110.25, accuracy: 0.0001)
    }

    func testCostZeroForEmptyUsage() {
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-4-7", usage: SessionUsage()), 0, accuracy: 0.0001)
    }

    func testContextWindow() {
        XCTAssertEqual(ModelPricing.contextWindow(for: "claude-opus-4-7"), 200_000)
        XCTAssertEqual(ModelPricing.contextWindow(for: nil), 200_000)
    }

    func testSessionUsageDerivedValues() {
        var usage = SessionUsage()
        usage.lastModel = "claude-opus-4-7"
        usage.lastContextTokens = 100_000
        XCTAssertEqual(usage.contextWindow, 200_000)
        XCTAssertEqual(usage.contextPercent, 50, accuracy: 0.001)
    }
}
