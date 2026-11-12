@testable import VSVibe
import XCTest

/// Uses a recording notifier, a fake session launcher and temp stores; the
/// events file lives in a temp directory.
@MainActor
internal final class EventCoordinatorTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var notifier = RecordingNotifier()
    private var fake = FakeSessionLauncher()

    private var eventsURL: URL { directory.appendingPathComponent("events.jsonl") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("coordinator")
        notifier = RecordingNotifier()
        fake = FakeSessionLauncher()
        fake.onPath.insert("ls")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStats() -> StatsStore {
        StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
    }

    private func makeManager(stats: StatsStore) -> SessionManager {
        SessionManager(
            statsStore: stats,
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher
        )
    }

    private func makeCoordinator(manager: SessionManager, stats: StatsStore) -> EventCoordinator {
        EventCoordinator(
            folderStore: FolderStore(fileURL: directory.appendingPathComponent("state.json")),
            sessionManager: manager,
            statsStore: stats,
            notifier: notifier,
            eventsURL: eventsURL
        )
    }

    private func makeProjectFolder(_ name: String) -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func event(_ kind: HookEventKind, _ dir: URL?, message: String? = nil) -> HookEvent {
        HookEvent(event: kind, projectDir: dir?.path ?? "", timestamp: 1_700_000_000, message: message)
    }

    // MARK: - Matching sessions

    internal func testNotificationMarksSessionAwaitingInput() throws {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.handle(event(.notification, folderURL, message: "Allow Bash?"))

        XCTAssertTrue(session.awaitingInput)
        XCTAssertEqual(session.unreadEventCount, 1)
        XCTAssertEqual(session.lastEventLabel, "Allow Bash?")
        XCTAssertEqual(session.lastEventAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(coordinator.lastEvent?.event, .notification)
        let post = try XCTUnwrap(notifier.posts.last)
        XCTAssertEqual(post.title, "alpha — Claude needs input")
        XCTAssertEqual(post.body, "Allow Bash?")
        XCTAssertEqual(post.sessionID, session.id)
        XCTAssertEqual(stats.summary(forFolderURL: folderURL, window: .today).notifications, 1)
        manager.closeAllSessions()
    }

    internal func testNotificationWithoutMessageUsesDefaults() throws {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.handle(event(.notification, folderURL))

        XCTAssertEqual(session.lastEventLabel, "Needs input")
        XCTAssertEqual(notifier.posts.last?.body, "Claude is waiting for input in alpha.")
        manager.closeAllSessions()
    }

    internal func testStopAndSubagentStopFinishTheTurn() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.handle(event(.notification, folderURL))
        coordinator.handle(event(.stop, folderURL, message: ""))
        XCTAssertFalse(session.awaitingInput)
        XCTAssertEqual(session.lastEventLabel, "Finished")
        XCTAssertEqual(notifier.posts.last?.body, "Claude finished a response in alpha.")

        coordinator.handle(event(.subagentStop, folderURL))
        XCTAssertEqual(session.unreadEventCount, 3)
        XCTAssertEqual(notifier.posts.last?.title, "alpha — Subagent finished")
        XCTAssertEqual(notifier.posts.last?.body, "Subagent finished in alpha.")

        let summary = stats.summary(forFolderURL: folderURL, window: .today)
        XCTAssertEqual(summary.finishes, 1)
        XCTAssertEqual(summary.subagentFinishes, 1)
        manager.closeAllSessions()
    }

    internal func testUnknownEventOnlyStampsTime() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.handle(event(.unknown, folderURL))

        XCTAssertEqual(session.unreadEventCount, 0)
        XCTAssertNil(session.lastEventLabel)
        XCTAssertNotNil(session.lastEventAt)
        XCTAssertEqual(notifier.posts.last?.body, "Event in alpha.")
        manager.closeAllSessions()
    }

    internal func testProjectDirMatchesThroughSymlinks() throws {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let link = directory.appendingPathComponent("alpha-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folderURL)
        let session = manager.createSession(for: FolderEntry(url: link, launchCommand: "ls"))

        coordinator.handle(event(.stop, folderURL))

        XCTAssertEqual(session.unreadEventCount, 1)
        XCTAssertEqual(notifier.posts.last?.sessionID, session.id)
        manager.closeAllSessions()
    }

    // MARK: - Unmatched events

    internal func testUnmatchedEventPostsGenericNotificationAndRecordsStats() throws {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let elsewhere = makeProjectFolder("elsewhere")

        coordinator.handle(event(.stop, elsewhere))

        let post = try XCTUnwrap(notifier.posts.last)
        XCTAssertEqual(post.title, "Claude finished")
        XCTAssertEqual(post.body, "Claude finished a response in elsewhere.")
        XCTAssertNil(post.sessionID)
        XCTAssertEqual(stats.summary(forFolderURL: elsewhere, window: .today).finishes, 1)
    }

    internal func testEventWithoutProjectDirPostsButRecordsNothing() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.handle(event(.notification, nil, message: "hello"))

        XCTAssertEqual(notifier.posts.count, 1)
        XCTAssertEqual(notifier.posts.last?.body, "hello")
        XCTAssertNil(notifier.posts.last?.sessionID)
        XCTAssertEqual(session.unreadEventCount, 0)
        XCTAssertFalse(stats.state.projects.isEmpty, "only the pane-open stat exists")
        XCTAssertEqual(stats.summary(forFolderURL: folderURL, window: .today).notifications, 0)
        manager.closeAllSessions()
    }

    // MARK: - Unread state

    internal func testClearUnreadResetsCounters() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let session = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))
        coordinator.handle(event(.notification, folderURL))

        coordinator.clearUnread(for: UUID())
        XCTAssertEqual(session.unreadEventCount, 1)

        coordinator.clearUnread(for: session.id)
        XCTAssertEqual(session.unreadEventCount, 0)
        XCTAssertFalse(session.awaitingInput)
        manager.closeAllSessions()
    }

    // MARK: - Watching

    internal func testStartWatchesEventsFileAndWiresActivation() async throws {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let coordinator = makeCoordinator(manager: manager, stats: stats)
        let folderURL = makeProjectFolder("alpha")
        let first = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))
        let second = manager.createSession(for: FolderEntry(url: folderURL, launchCommand: "ls"))

        coordinator.start()
        XCTAssertTrue(coordinator.isWatching)
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsURL.path))

        let activate = try XCTUnwrap(notifier.activationHandler)
        activate(first.id)
        XCTAssertEqual(manager.focusedSessionID, first.id)
        XCTAssertNotEqual(manager.focusedSessionID, second.id)

        let line = #"{"event":"Stop","projectDir":"\#(folderURL.path)","ts":1}"# + "\n"
        let handle = try FileHandle(forWritingTo: eventsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()

        let delivered = await AsyncWait.until { coordinator.lastEvent != nil }
        XCTAssertTrue(delivered)
        XCTAssertEqual(coordinator.lastEvent?.event, .stop)

        coordinator.stop()
        XCTAssertFalse(coordinator.isWatching)
        manager.closeAllSessions()
    }

    internal func testStopBeforeStartIsHarmless() {
        let stats = makeStats()
        let coordinator = makeCoordinator(manager: makeManager(stats: stats), stats: stats)
        coordinator.stop()
        XCTAssertFalse(coordinator.isWatching)
        XCTAssertNil(coordinator.lastEvent)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
