@testable import VSVibe
import XCTest

/// Which transcript each pane's usage tracker follows: the launch alias's
/// latest transcript first, the pane's own transcript once known.
@MainActor
internal final class SessionManagerUsageTests: XCTestCase {
    private var directory = TestSupport.placeholderURL
    private var fake = FakeSessionLauncher()

    private var workConfig: URL { directory.appendingPathComponent("claude-work", isDirectory: true) }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("usage-panes")
        fake = FakeSessionLauncher()
        fake.onPath.formUnion(["work", "plain", "ls"])
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func makeManager() throws -> SessionManager {
        let aliases = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        try aliases.save(command: "work", configPath: workConfig.path)
        return SessionManager(
            statsStore: StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] },
            aliasStore: aliases,
            launcher: fake.launcher
        )
    }

    private func makeFolder(command: String) -> FolderEntry {
        let url = directory.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FolderEntry(url: url, launchCommand: command)
    }

    /// Writes a transcript with `messages` assistant messages and returns its path.
    private func writeTranscript(_ name: String, messages: Int, config: URL? = nil) throws -> String {
        let folder = makeFolder(command: "work").url
        let dir = TranscriptLocator.projectDir(claudeConfigDir: config ?? workConfig, folderURL: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = TestSupport.jsonl(["type": "assistant", "message": ["usage": ["input_tokens": 1]]])
        let url = dir.appendingPathComponent("\(name).jsonl")
        TestSupport.write(String(repeating: line, count: messages), to: url)
        return url.path
    }

    private func source(of session: TerminalSession, in manager: SessionManager) -> TranscriptSource? {
        manager.usageTrackers[session.id]?.source
    }

    internal func testPaneStartsOnLatestThenFollowsItsOwnTranscript() throws {
        let manager = try makeManager()
        let folder = makeFolder(command: "work --continue")
        let pane = manager.createSession(for: folder)
        XCTAssertEqual(source(of: pane, in: manager), .latest(folderURL: folder.url, configDir: workConfig))

        manager.recordClaudeConversation("conv-1", transcriptPath: "/c/projects/p/conv-1.jsonl", in: pane)
        XCTAssertEqual(source(of: pane, in: manager), .file(URL(fileURLWithPath: "/c/projects/p/conv-1.jsonl")))
        XCTAssertEqual(pane.claudeSessionID, "conv-1")

        // After /clear the pane reports a new conversation: retarget.
        pane.usage = SessionUsage()
        manager.recordClaudeConversation("conv-2", transcriptPath: "/c/projects/p/conv-2.jsonl", in: pane)
        XCTAssertEqual(source(of: pane, in: manager), .file(URL(fileURLWithPath: "/c/projects/p/conv-2.jsonl")))
        XCTAssertNil(pane.usage, "Usage of the previous conversation is cleared")

        // The same path again keeps the running tracker (and its usage).
        let tracker = manager.usageTrackers[pane.id]
        pane.usage = SessionUsage()
        manager.recordClaudeConversation("conv-2", transcriptPath: "/c/projects/p/conv-2.jsonl", in: pane)
        XCTAssertTrue(manager.usageTrackers[pane.id] === tracker)
        XCTAssertNotNil(pane.usage)

        // An unknown path falls back to the alias's latest transcript.
        manager.recordClaudeConversation("conv-3", transcriptPath: nil, in: pane)
        XCTAssertEqual(source(of: pane, in: manager), .latest(folderURL: folder.url, configDir: workConfig))
        manager.closeAllSessions()
        XCTAssertTrue(manager.usageTrackers.isEmpty)
    }

    internal func testPaneWithoutAliasStartsTrackingOnceItReportsATranscript() throws {
        let manager = try makeManager()
        let pane = manager.createSession(for: makeFolder(command: "plain"))
        XCTAssertNil(manager.usageTrackers[pane.id])

        manager.recordClaudeConversation("conv", transcriptPath: "/other/projects/p/conv.jsonl", in: pane)
        XCTAssertEqual(source(of: pane, in: manager), .file(URL(fileURLWithPath: "/other/projects/p/conv.jsonl")))

        manager.recordClaudeConversation("conv", transcriptPath: nil, in: pane)
        XCTAssertNil(manager.usageTrackers[pane.id])
        manager.closeAllSessions()
    }

    internal func testClosedPaneIsNotTracked() throws {
        let manager = try makeManager()
        let pane = manager.createSession(for: makeFolder(command: "plain"))
        manager.closeSession(id: pane.id)
        manager.recordClaudeConversation("conv", transcriptPath: "/c/projects/p/conv.jsonl", in: pane)
        XCTAssertNil(manager.usageTrackers[pane.id])
        XCTAssertEqual(pane.claudeTranscriptPath, "/c/projects/p/conv.jsonl")
    }

    internal func testRestoredPaneTracksItsTranscriptImmediately() throws {
        let manager = try makeManager()
        let pane = manager.restoreSession(
            for: makeFolder(command: "plain"),
            command: "work --resume conv",
            claudeSessionID: "conv",
            transcriptPath: "/c/projects/p/conv.jsonl"
        )
        XCTAssertEqual(source(of: pane, in: manager), .file(URL(fileURLWithPath: "/c/projects/p/conv.jsonl")))
        manager.closeAllSessions()
    }

    internal func testTwoPanesInOneFolderShowTheirOwnConversations() async throws {
        let manager = try makeManager()
        let folder = makeFolder(command: "work")
        let first = manager.createSession(for: folder)
        let second = manager.createSession(for: folder)
        let small = try writeTranscript("small", messages: 1)
        // The other pane's conversation runs under a different account.
        let large = try writeTranscript("large", messages: 3, config: directory.appendingPathComponent("other"))

        manager.recordClaudeConversation("small", transcriptPath: small, in: first)
        manager.recordClaudeConversation("large", transcriptPath: large, in: second)

        let delivered = await AsyncWait.until { first.usage != nil && second.usage != nil }
        XCTAssertTrue(delivered)
        XCTAssertEqual(first.usage?.messageCount, 1)
        XCTAssertEqual(second.usage?.messageCount, 3)
        manager.closeAllSessions()
    }

    deinit {
        // The temp dir is removed in tearDown.
    }
}
