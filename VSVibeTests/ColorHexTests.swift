@testable import VSVibe
import XCTest

internal final class ColorHexTests: XCTestCase {
    internal func testParsesSixDigitWithHash() {
        let rgb = ColorHex.rgb(from: "#FF8000")
        XCTAssertEqual(rgb?.red ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.green ?? 0, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb?.blue ?? 0, 0.0, accuracy: 0.001)
    }

    internal func testParsesWithoutHashAndLowercase() {
        XCTAssertEqual(ColorHex.rgb(from: "ff8000"), ColorHex.rgb(from: "#FF8000"))
    }

    internal func testParsesShorthand() {
        XCTAssertEqual(ColorHex.rgb(from: "#abc"), ColorHex.rgb(from: "#AABBCC"))
    }

    internal func testTrimsWhitespace() {
        XCTAssertEqual(ColorHex.rgb(from: "  #3B82F6 "), ColorHex.rgb(from: "#3B82F6"))
    }

    internal func testRejectsInvalid() {
        XCTAssertNil(ColorHex.rgb(from: ""))
        XCTAssertNil(ColorHex.rgb(from: "#GGGGGG"))
        XCTAssertNil(ColorHex.rgb(from: "#12345"))
        XCTAssertNil(ColorHex.rgb(from: "blue"))
        XCTAssertNil(ColorHex.rgb(from: "#12345678"))
    }

    internal func testNormalizedUppercasesAndAddsHash() {
        XCTAssertEqual(ColorHex.normalized("3b82f6"), "#3B82F6")
        XCTAssertEqual(ColorHex.normalized("#abc"), "#AABBCC")
        XCTAssertNil(ColorHex.normalized("nope"))
    }

    internal func testNormalizedIsIdempotent() throws {
        let once = try XCTUnwrap(ColorHex.normalized("#3b82f6"))
        XCTAssertEqual(ColorHex.normalized(once), once)
    }

    deinit {
        // Nothing to release.
    }
}
