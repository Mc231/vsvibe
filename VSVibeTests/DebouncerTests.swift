@testable import VSVibe
import XCTest

@MainActor
internal final class DebouncerTests: XCTestCase {
    internal func testOnlyLastCallRunsAfterInterval() async {
        let debouncer = Debouncer(interval: 0.05)
        let lastRan = expectation(description: "last action runs")
        var calls: [String] = []
        debouncer.call { calls.append("first") }
        debouncer.call { calls.append("second") }
        debouncer.call {
            calls.append("third")
            lastRan.fulfill()
        }
        await fulfillment(of: [lastRan], timeout: 5)
        XCTAssertEqual(calls, ["third"])
    }

    internal func testActionDoesNotRunBeforeInterval() async {
        let debouncer = Debouncer(interval: 0.3)
        let ran = expectation(description: "action must not run early")
        ran.isInverted = true
        debouncer.call { ran.fulfill() }
        await fulfillment(of: [ran], timeout: 0.1)
        debouncer.flush()
    }

    internal func testFlushRunsPendingImmediatelyAndOnlyOnce() async {
        let debouncer = Debouncer(interval: 0.05)
        var count = 0
        debouncer.call { count += 1 }
        debouncer.flush()
        XCTAssertEqual(count, 1)

        // The cancelled scheduled run must not fire afterwards.
        let noSecondRun = expectation(description: "no second run")
        noSecondRun.isInverted = true
        await fulfillment(of: [noSecondRun], timeout: 0.2)
        XCTAssertEqual(count, 1)

        // Nothing pending: flushing again is a no-op.
        debouncer.flush()
        XCTAssertEqual(count, 1)
    }

    internal func testFlushAfterActionFiredDoesNotRepeatIt() async {
        let debouncer = Debouncer(interval: 0.05)
        let fired = expectation(description: "action fires")
        var count = 0
        debouncer.call {
            count += 1
            fired.fulfill()
        }
        await fulfillment(of: [fired], timeout: 5)
        debouncer.flush()
        XCTAssertEqual(count, 1)
    }

    internal func testFlushWithoutPendingWorkDoesNothing() {
        let debouncer = Debouncer(interval: 1)
        debouncer.flush()
        var ran = false
        debouncer.call { ran = true }
        debouncer.flush()
        XCTAssertTrue(ran)
    }

    deinit {
        // No shared state to release.
    }
}
