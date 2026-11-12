@testable import VSVibe
import XCTest

internal final class StatWindowTests: XCTestCase {
    internal func testAllCasesKeepDisplayOrder() {
        XCTAssertEqual(StatWindow.allCases, [.today, .last7, .last30, .allTime])
    }

    internal func testIdsAreStableCaseNames() {
        XCTAssertEqual(StatWindow.allCases.map(\.id), ["today", "last7", "last30", "allTime"])
    }

    internal func testLabels() {
        XCTAssertEqual(StatWindow.allCases.map(\.label), ["Today", "7 days", "30 days", "All time"])
    }

    internal func testDays() {
        XCTAssertEqual(StatWindow.allCases.map(\.days), [1, 7, 30, nil])
    }

    deinit {
        // No shared state to release.
    }
}
