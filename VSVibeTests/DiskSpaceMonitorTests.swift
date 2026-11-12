@testable import VSVibe
import XCTest

@MainActor
internal final class DiskSpaceMonitorTests: XCTestCase {
    internal func testInitialRefreshReadsRootVolume() {
        let monitor = DiskSpaceMonitor()
        XCTAssertGreaterThan(monitor.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(monitor.availableBytes, 0)
        XCTAssertLessThanOrEqual(monitor.availableBytes, monitor.totalBytes)
        XCTAssertFalse(monitor.totalLabel.isEmpty)
        XCTAssertFalse(monitor.availableLabel.isEmpty)
    }

    internal func testStartAndStopAreIdempotent() {
        let monitor = DiskSpaceMonitor()
        monitor.start()
        monitor.start()
        monitor.stop()
        monitor.stop()
        monitor.refresh()
        XCTAssertGreaterThan(monitor.totalBytes, 0)
    }

    internal func testMonitorIsReleasedAfterUse() {
        weak var weakMonitor: DiskSpaceMonitor?
        do {
            let monitor = DiskSpaceMonitor()
            monitor.start()
            monitor.stop()
            weakMonitor = monitor
        }
        XCTAssertNil(weakMonitor)
    }

    deinit {
        // No shared state to release.
    }
}
