@testable import VSVibe
import XCTest

internal final class ModelRatesTests: XCTestCase {
    internal func testFamilyRates() {
        XCTAssertEqual(ModelRates.opus, ModelRates(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5))
        XCTAssertEqual(ModelRates.sonnet, ModelRates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3))
        XCTAssertEqual(ModelRates.haiku, ModelRates(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1))
    }

    internal func testPricingFallsBackByFamilyName() {
        XCTAssertEqual(ModelPricing.rates(for: "vendor-haiku-next"), .haiku)
        XCTAssertEqual(ModelPricing.rates(for: "vendor-sonnet-next"), .sonnet)
        XCTAssertEqual(ModelPricing.rates(for: "vendor-opus-next"), .opus)
        XCTAssertEqual(ModelPricing.rates(for: "unknown-model"), .opus)
        XCTAssertEqual(ModelPricing.rates(for: nil), .opus)
    }

    internal func testExactPrefixesMapToFamilies() {
        XCTAssertEqual(ModelPricing.rates(for: "claude-3-5-haiku-20241022"), .haiku)
        XCTAssertEqual(ModelPricing.rates(for: "claude-3-5-sonnet-20241022"), .sonnet)
        XCTAssertEqual(ModelPricing.rates(for: "claude-opus-4-20250514"), .opus)
    }

    deinit {
        // No shared state to release.
    }
}
