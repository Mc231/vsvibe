@testable import VSVibe
import XCTest

internal final class FormatTests: XCTestCase {
    internal func testCost() {
        XCTAssertEqual(Format.cost(0), "$0.00")
        XCTAssertEqual(Format.cost(12.5), "$12.50")
        XCTAssertEqual(Format.cost(150), "$150")
    }

    internal func testTokens() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(1_200), "1k")
        XCTAssertEqual(Format.tokens(1_500_000), "1.5M")
    }

    internal func testDuration() {
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(90), "1m")
        XCTAssertEqual(Format.duration(3_661), "1h 1m")
    }

    internal func testModelPrettify() {
        XCTAssertEqual(Format.model("claude-opus-4-7"), "Opus 4.7")
        XCTAssertEqual(Format.model("claude-sonnet-4-6"), "Sonnet 4.6")
        XCTAssertEqual(Format.model("opus"), "Opus")
    }

    deinit {
        // Nothing to release.
    }
}
