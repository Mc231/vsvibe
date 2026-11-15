@testable import VSVibe
import XCTest

/// Routing hook events by `paneId` (several panes per folder), recording each
/// pane's Claude session id, and naming notifications after the project.
@MainActor
internal final class EventCoordinatorPaneTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var notifier = RecordingNotifier()
    private var fake = FakeSessionLauncher()
    private var folderStore = FolderStore(fileURL: TestSupport.placeholderURL)
    private var manager = SessionManager(
        statsStore: StatsStore(fileURL: TestSupport.placeholderURL) { [] },
        aliasStore: LaunchAliasStore(fileURL: TestSupport.placeholderURL)
    )
    private var coordinator: EventCoordinator?

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("coordinator-panes")
        notifier = RecordingNotifier()
        fake = FakeSessionLauncher()
        fake.onPath.insert("ls")
        folderStore = FolderStore(fileURL: directory.appendingPathComponent("state.json"))
        let stats = StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
        manager = SessionManager(
            statsStore: stats,
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher
        )
        coordinator = EventCoordinator(
            folderStore: folderStore,
            sessionManager: manager,
            statsStore: stats,
            notifier: notifier,
            eventsURL: directory.appendingPathComponent("events.jsonl")
        )
    }

    override internal func tearDown() {
        manager.closeAllSessions()
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func handle(
        _ kind: HookEventKind,
        dir: URL,
        paneID: UUID? = nil,
        claudeSessionID: String? = nil,
        transcriptPath: String? = nil
    ) throws {
        let event = HookEvent(
            event: kind,
            projectDir: dir.path,
            timestamp: 1,
            message: nil,
            paneID: paneID,
            claudeSessionID: claudeSessionID,
            transcriptPath: transcriptPath
        )
        try XCTUnwrap(coordinator).handle(event)
    }

    private func makeProject(_ name: String) -> FolderEntry {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return folderStore.createProject(url: url, name: name, launchCommand: "ls")
    }

    internal func testPaneIDRoutesToTheRightPaneInASharedFolder() throws {
        let folder = makeProject("alpha")
        let first = manager.createSession(for: folder)
        let second = manager.createSession(for: folder)

        try handle(.notification, dir: folder.url, paneID: second.id, claudeSessionID: "conv-2")

        XCTAssertEqual(first.unreadEventCount, 0)
        XCTAssertNil(first.claudeSessionID)
        XCTAssertEqual(second.unreadEventCount, 1)
        XCTAssertTrue(second.awaitingInput)
        XCTAssertEqual(second.claudeSessionID, "conv-2")
        XCTAssertEqual(notifier.posts.last?.sessionID, second.id)
    }

    internal func testLatestClaudeSessionIDWins() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)

        try handle(.sessionStart, dir: folder.url, paneID: pane.id, claudeSessionID: "before-clear")
        try handle(.sessionStart, dir: folder.url, paneID: pane.id, claudeSessionID: "after-clear")

        XCTAssertEqual(pane.claudeSessionID, "after-clear")
    }

    internal func testRecordsAValidTranscriptPathWithTheID() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)
        let path = "/Users/u/.claude-work/projects/-alpha/conv-1.jsonl"

        try handle(.sessionStart, dir: folder.url, paneID: pane.id, claudeSessionID: "conv-1", transcriptPath: path)
        XCTAssertEqual(pane.claudeTranscriptPath, path)

        // A new conversation without a path drops the old conversation's path.
        try handle(.sessionStart, dir: folder.url, paneID: pane.id, claudeSessionID: "conv-2")
        XCTAssertEqual(pane.claudeSessionID, "conv-2")
        XCTAssertNil(pane.claudeTranscriptPath)
    }

    internal func testInvalidTranscriptPathsAreNotRecorded() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)
        let invalid = [
            "relative/projects/p/conv-1.jsonl",
            "/c/projects/p/other-id.jsonl",
            "/c/projects/p/conv-1.json",
            "/c/projects/p\n/conv-1.jsonl"
        ]

        for path in invalid {
            try handle(.stop, dir: folder.url, paneID: pane.id, claudeSessionID: "conv-1", transcriptPath: path)
            XCTAssertEqual(pane.claudeSessionID, "conv-1")
            XCTAssertNil(pane.claudeTranscriptPath, path)
        }

        // Another pane's event never sets this pane's path.
        try handle(.stop, dir: folder.url, claudeSessionID: "conv-9", transcriptPath: "/c/projects/p/conv-9.jsonl")
        XCTAssertNil(pane.claudeTranscriptPath)
    }

    internal func testSessionStartOnlyRecordsTheID() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)

        try handle(.sessionStart, dir: folder.url, paneID: pane.id, claudeSessionID: "conv-1")
        try handle(.sessionStart, dir: directory.appendingPathComponent("elsewhere"), claudeSessionID: "other")

        XCTAssertEqual(pane.claudeSessionID, "conv-1")
        XCTAssertEqual(pane.unreadEventCount, 0)
        XCTAssertNil(pane.lastEventAt)
        XCTAssertTrue(notifier.posts.isEmpty)
        XCTAssertEqual(try XCTUnwrap(coordinator).lastEvent?.event, .sessionStart)
    }

    internal func testFolderMatchDoesNotAssignAClaudeSessionID() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)

        try handle(.stop, dir: folder.url, claudeSessionID: "ambiguous")
        try handle(.stop, dir: folder.url, paneID: UUID(), claudeSessionID: "stale-pane")

        XCTAssertNil(pane.claudeSessionID)
        XCTAssertEqual(pane.unreadEventCount, 2, "unknown pane ids fall back to the folder match")
    }

    internal func testUnsafeClaudeSessionIDIsIgnored() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)

        try handle(.stop, dir: folder.url, paneID: pane.id, claudeSessionID: "x; rm -rf ~")

        XCTAssertNil(pane.claudeSessionID)
        XCTAssertEqual(pane.unreadEventCount, 1)
    }

    /// Regression: the title used to look the project up by the pane's id, so
    /// it never found it and always showed the name from when the pane opened.
    internal func testNotificationUsesTheProjectsCurrentName() throws {
        let folder = makeProject("alpha")
        let pane = manager.createSession(for: folder)
        folderStore.updateProject(id: folder.id, name: "Renamed", launchCommand: "ls")

        try handle(.stop, dir: folder.url, paneID: pane.id)

        XCTAssertEqual(notifier.posts.last?.title, "Renamed — Claude finished")
        XCTAssertEqual(notifier.posts.last?.body, "Claude finished a response in Renamed.")
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
