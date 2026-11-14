@testable import VSVibe
import XCTest

@MainActor
internal final class RelaunchGuardTests: XCTestCase {
    internal func testNoSessionsRelaunchesWithoutAsking() {
        let relaunchGuard = RelaunchGuard { 0 }
        var asked = false
        let postpone = relaunchGuard.shouldPostponeRelaunch { _ in
            asked = true
            return false
        }
        XCTAssertFalse(postpone)
        XCTAssertFalse(asked)
        XCTAssertNil(relaunchGuard.prompt())
    }

    internal func testConfirmedRelaunchProceeds() {
        let relaunchGuard = RelaunchGuard { 3 }
        var shown: RelaunchGuard.Prompt?
        let postpone = relaunchGuard.shouldPostponeRelaunch { prompt in
            shown = prompt
            return true
        }
        XCTAssertFalse(postpone)
        XCTAssertEqual(shown, relaunchGuard.prompt())
        XCTAssertEqual(shown?.confirmTitle, "Install and Relaunch")
        XCTAssertEqual(shown?.cancelTitle, "Later")
        XCTAssertEqual(shown?.title, "Install the update and relaunch VSVibe?")
        XCTAssertEqual(shown?.message.hasPrefix("3 sessions are running and will be closed."), true)
    }

    internal func testDeclinedRelaunchIsPostponed() {
        let relaunchGuard = RelaunchGuard { 1 }
        XCTAssertTrue(relaunchGuard.shouldPostponeRelaunch { _ in false })
        XCTAssertEqual(relaunchGuard.prompt()?.message.hasPrefix("1 session is running"), true)
    }

    internal func testCountIsReadAtDecisionTime() {
        var count = 0
        let relaunchGuard = RelaunchGuard { count }
        XCTAssertNil(relaunchGuard.prompt())
        count = 2
        XCTAssertNotNil(relaunchGuard.prompt())
    }

    internal func testUpdaterDoesNotStartWhileHostingTests() {
        XCTAssertFalse(UpdaterLaunchPolicy.shouldStartUpdater(environment: ProcessInfo.processInfo.environment))
        XCTAssertFalse(UpdaterLaunchPolicy.shouldStartUpdater(environment: ["XCTestConfigurationFilePath": "/x"]))
        XCTAssertTrue(UpdaterLaunchPolicy.shouldStartUpdater(environment: ["HOME": "/Users/me"]))
    }

    deinit {
        // No shared state to release.
    }
}
