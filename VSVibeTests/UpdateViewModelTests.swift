@testable import VSVibe
import XCTest

@MainActor
internal final class UpdateViewModelTests: XCTestCase {
    private let info: [String: Any] = ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "123"]

    internal func testInitialStateMirrorsUpdater() {
        let updater = FakeUpdater()
        updater.automaticallyChecksForUpdates = false
        let model = UpdateViewModel(updater: updater, infoDictionary: info)
        XCTAssertFalse(model.automaticallyChecksForUpdates)
        XCTAssertFalse(model.automaticallyDownloadsUpdates)
        XCTAssertFalse(model.canCheckForUpdates)
        XCTAssertEqual(model.versionDescription, "Version 0.2.0 (123)")
    }

    internal func testVersionDescriptionFallsBackWhenKeysMissing() {
        XCTAssertEqual(UpdateViewModel.versionDescription(infoDictionary: [:]), "Version ? (?)")
        XCTAssertEqual(
            UpdateViewModel.versionDescription(infoDictionary: ["CFBundleVersion": 7]),
            "Version ? (?)"
        )
    }

    internal func testCanCheckFollowsPublisher() async {
        let updater = FakeUpdater()
        let model = UpdateViewModel(updater: updater, infoDictionary: info)
        updater.setCanCheck(true)
        let enabled = await AsyncWait.until { model.canCheckForUpdates }
        XCTAssertTrue(enabled)
        updater.setCanCheck(false)
        let disabled = await AsyncWait.until { !model.canCheckForUpdates }
        XCTAssertTrue(disabled)
    }

    internal func testCheckForUpdatesOnlyWhenAllowed() async {
        let updater = FakeUpdater()
        let model = UpdateViewModel(updater: updater, infoDictionary: info)
        model.checkForUpdates()
        XCTAssertEqual(updater.checkCount, 0)
        updater.setCanCheck(true)
        await AsyncWait.until { model.canCheckForUpdates }
        model.checkForUpdates()
        XCTAssertEqual(updater.checkCount, 1)
    }

    internal func testTogglesWriteThroughAndReadBack() {
        let updater = FakeUpdater()
        let model = UpdateViewModel(updater: updater, infoDictionary: info)
        model.setAutomaticallyDownloadsUpdates(true)
        XCTAssertTrue(model.automaticallyDownloadsUpdates)

        model.setAutomaticallyChecksForUpdates(false)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(model.automaticallyChecksForUpdates)
        XCTAssertFalse(model.automaticallyDownloadsUpdates, "downloads are off while checks are off")

        model.setAutomaticallyChecksForUpdates(true)
        XCTAssertTrue(model.automaticallyChecksForUpdates)
        XCTAssertTrue(model.automaticallyDownloadsUpdates)
    }

    deinit {
        // No shared state to release.
    }
}
