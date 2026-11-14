import AppKit
@testable import VSVibe
import XCTest

/// Panes come from `FakeSessionLauncher`; the snapshot file, stores and
/// defaults suite are temporary; termination is posted on a private center.
@MainActor
internal final class SessionRestoreControllerTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var fake = FakeSessionLauncher()
    private var suiteName = ""
    private var defaults = UserDefaults()
    private var center = NotificationCenter()
    private var folderStore = FolderStore(fileURL: TestSupport.placeholderURL)
    private var manager = SessionManager(
        statsStore: StatsStore(fileURL: TestSupport.placeholderURL) { [] },
        aliasStore: LaunchAliasStore(fileURL: TestSupport.placeholderURL)
    )

    private var fileURL: URL { directory.appendingPathComponent("sessions.json") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("restore")
        fake = FakeSessionLauncher()
        fake.onPath = ["ls", "claude"]
        suiteName = "vsvibe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults()
        center = NotificationCenter()
        folderStore = FolderStore(fileURL: directory.appendingPathComponent("state.json"))
        manager = SessionManager(
            statsStore: StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] },
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher
        )
    }

    override internal func tearDown() {
        manager.closeAllSessions()
        defaults.removePersistentDomain(forName: suiteName)
        TestSupport.remove(directory)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeController(saveDelay: TimeInterval = 0.05) -> SessionRestoreController {
        SessionRestoreController(
            sessionManager: manager,
            folderStore: folderStore,
            settings: SessionRestoreSettings(defaults: defaults),
            fileURL: fileURL,
            saveDelay: saveDelay,
            notificationCenter: center
        ) { command in
            LaunchCommandResolver.alias(for: LaunchCommandResolver.baseCommand(of: command))
        }
    }

    private func makeProject(_ name: String, command: String = "claude") -> FolderEntry {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return folderStore.createProject(url: url, name: name, launchCommand: command)
    }

    private func writeSnapshot(folderIDs: [FolderEntry.ID]) {
        let panes = folderIDs.map { PaneSnapshot(folderID: $0, claudeSessionID: nil) }
        SessionSnapshotFile.write(SessionSnapshot(panes: panes), to: fileURL)
    }

    private func saved() -> SessionSnapshot? {
        SessionSnapshotFile.read(from: fileURL)
    }

    // MARK: - Restore

    internal func testRestoresPanesInOrderWithFocusAndConversations() async {
        let alpha = makeProject("alpha")
        let beta = makeProject("beta", command: "ls")
        SessionSnapshotFile.write(
            SessionSnapshot(
                panes: [
                    PaneSnapshot(folderID: alpha.id, claudeSessionID: "conv-a"),
                    PaneSnapshot(folderID: UUID(), claudeSessionID: "gone"),
                    PaneSnapshot(folderID: beta.id, claudeSessionID: nil),
                    PaneSnapshot(folderID: alpha.id, claudeSessionID: "conv-b")
                ],
                focusedIndex: 2
            ),
            to: fileURL
        )
        let controller = makeController()

        controller.start()

        XCTAssertTrue(controller.isStarted)
        XCTAssertEqual(manager.sessions.map(\.folder.id), [alpha.id, beta.id, alpha.id])
        XCTAssertEqual(manager.sessions.map(\.claudeSessionID), ["conv-a", nil, "conv-b"])
        XCTAssertEqual(manager.focusedSessionID, manager.sessions[1].id)
        // The restored panes (new ids, same conversations) are saved back.
        let rewritten = await AsyncWait.until { self.saved()?.panes.count == 3 }
        XCTAssertTrue(rewritten)
        XCTAssertEqual(saved()?.panes.map(\.claudeSessionID), ["conv-a", nil, "conv-b"])
        XCTAssertEqual(saved()?.focusedIndex, 1)
    }

    internal func testStartRunsOnlyOnce() {
        let alpha = makeProject("alpha")
        writeSnapshot(folderIDs: [alpha.id])
        let controller = makeController()

        controller.start()
        controller.start()

        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertNotNil(manager.focusedSessionID, "the first pane takes focus when none was saved")
    }

    internal func testNoFileOpensNothing() {
        makeController().start()
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    internal func testDisabledOpensNothingAndRemovesTheFile() async {
        defaults.set(false, forKey: SessionRestoreSettings.key)
        let alpha = makeProject("alpha")
        writeSnapshot(folderIDs: [alpha.id])

        let controller = makeController()
        controller.start()
        manager.createSession(for: alpha)

        XCTAssertTrue(controller.isStarted)
        XCTAssertEqual(manager.sessions.count, 1, "only the pane opened by hand")
        let removed = await AsyncWait.until { !FileManager.default.fileExists(atPath: self.fileURL.path) }
        XCTAssertTrue(removed)
    }

    // MARK: - Saving

    internal func testSavesWheneverPanesOrConversationsChange() async {
        let alpha = makeProject("alpha")
        let controller = makeController()
        controller.start()

        let pane = manager.createSession(for: alpha)
        let opened = await AsyncWait.until { self.saved()?.panes.count == 1 }
        XCTAssertTrue(opened)

        pane.claudeSessionID = "conv-1"
        let recorded = await AsyncWait.until { self.saved()?.panes.first?.claudeSessionID == "conv-1" }
        XCTAssertTrue(recorded)

        manager.closeSession(id: pane.id)
        let closed = await AsyncWait.until { self.saved()?.panes.isEmpty == true }
        XCTAssertTrue(closed)
    }

    internal func testTerminationSavesImmediatelyUntilStopped() {
        let alpha = makeProject("alpha")
        let controller = makeController(saveDelay: 60)
        controller.start()
        manager.createSession(for: alpha)
        XCTAssertNil(saved(), "the debounced save has not fired yet")

        center.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(saved()?.panes.map(\.folderID), [alpha.id])

        controller.stop()
        controller.stop()
        manager.createSession(for: alpha)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(saved()?.panes.count, 1)
    }

    internal func testSaveNowWritesTheCurrentPanes() {
        let alpha = makeProject("alpha")
        let controller = makeController(saveDelay: 60)
        manager.createSession(for: alpha)

        controller.save()

        XCTAssertEqual(saved()?.panes.map(\.folderID), [alpha.id])
        XCTAssertEqual(saved()?.focusedIndex, 0)
    }

    // MARK: - Environment and settings

    internal func testDetectsTheUnitTestHost() {
        XCTAssertTrue(SessionRestoreController.isUnitTestHost(environment: ["XCTestConfigurationFilePath": "/x"]))
        XCTAssertFalse(SessionRestoreController.isUnitTestHost(environment: ["HOME": "/Users/me"]))
    }

    internal func testSettingIsOnByDefault() {
        XCTAssertTrue(SessionRestoreSettings(defaults: defaults).isEnabled)
        defaults.set(false, forKey: SessionRestoreSettings.key)
        XCTAssertFalse(SessionRestoreSettings(defaults: defaults).isEnabled)
        defaults.set(true, forKey: SessionRestoreSettings.key)
        XCTAssertTrue(SessionRestoreSettings(defaults: defaults).isEnabled)
        XCTAssertEqual(SessionRestoreSettings.key, "restoreSessionsOnLaunch")
    }

    deinit {
        // Temp directories and the defaults suite are removed in tearDown.
    }
}
