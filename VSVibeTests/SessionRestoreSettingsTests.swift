@testable import VSVibe
import XCTest

internal final class SessionRestoreSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()

    override internal func setUp() {
        super.setUp()
        suiteName = "vsvibe-settings-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults()
    }

    override internal func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    internal func testRestoreIsOnByDefaultSoARelaunchLosesNothing() {
        let settings = SessionRestoreSettings(defaults: defaults)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.sessionsLostOnRelaunch(running: 3), 0)
    }

    internal func testWithRestoreOffEveryRunningPaneIsLost() {
        defaults.set(false, forKey: SessionRestoreSettings.key)
        let settings = SessionRestoreSettings(defaults: defaults)

        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.sessionsLostOnRelaunch(running: 3), 3)
        XCTAssertEqual(settings.sessionsLostOnRelaunch(running: 0), 0)
    }

    deinit {
        // Each test's defaults suite is removed in tearDown.
    }
}
