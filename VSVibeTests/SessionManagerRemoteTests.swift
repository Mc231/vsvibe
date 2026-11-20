@testable import VSVibe
import XCTest

/// Remote (SSH) panes: what is spawned and typed, the conversation id they
/// record, restore, and the local trackers they must not start.
@MainActor
internal final class SessionManagerRemoteTests: XCTestCase {
    private var directory = TestSupport.placeholderURL
    private var fake = FakeSessionLauncher()

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("sessions-remote")
        fake = FakeSessionLauncher()
        fake.onPath = ["ssh"]
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func makeManager(stats: StatsStore? = nil) -> SessionManager {
        SessionManager(
            statsStore: stats ?? StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] },
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher
        )
    }

    private func remote(_ target: RemoteTarget = RemoteTarget(destination: "dev", remotePath: "~/app")) -> FolderEntry {
        FolderEntry(remote: target)
    }

    internal func testFreshPaneTypesTheSSHLineAndRecordsItsConversation() async throws {
        let stats = StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
        let manager = makeManager(stats: stats)
        let folder = remote()

        let session = manager.createSession(for: folder)
        await AsyncWait.drainMainQueue()

        let id = try XCTUnwrap(session.claudeSessionID)
        XCTAssertTrue(LaunchCommandResolver.isValidClaudeSessionID(id))
        XCTAssertNil(session.claudeTranscriptPath)
        XCTAssertEqual(fake.spawnedFolders, [FileManager.default.homeDirectoryForCurrentUser])
        let expected = SSHCommand.line(
            for: try XCTUnwrap(folder.remote),
            paneID: session.id,
            invocation: .command("claude --session-id \(id)")
        )
        XCTAssertEqual(fake.typedCommands, [try expected.get()])
        XCTAssertEqual(manager.snapshot.panes.map(\.claudeSessionID), [id])
        XCTAssertNil(session.errorMessage)
        XCTAssertNil(manager.usageTrackers[session.id], "remote transcripts are not tracked locally")
        XCTAssertNil(session.gitBranch)
        XCTAssertEqual(stats.summary(forFolderURL: folder.url, window: .today).panesOpened, 1)
        manager.closeAllSessions()
    }

    internal func testRestoreResumesTheSavedConversation() async throws {
        let manager = makeManager()
        let folder = remote()

        let session = manager.restoreSession(for: folder, command: "claude", claudeSessionID: "conv-1")
        await AsyncWait.drainMainQueue()

        XCTAssertEqual(session.claudeSessionID, "conv-1")
        let expected = SSHCommand.line(
            for: try XCTUnwrap(folder.remote),
            paneID: session.id,
            invocation: .resumeOrStart(command: "claude", claudeSessionID: "conv-1")
        )
        XCTAssertEqual(fake.typedCommands, [try expected.get()])
        manager.closeAllSessions()
    }

    internal func testHookConversationOverridesWithoutLocalTracking() {
        let manager = makeManager()
        let session = manager.createSession(for: remote())

        let path = "/home/me/.claude/projects/x/after-clear.jsonl"
        manager.recordClaudeConversation("after-clear", transcriptPath: path, in: session)

        XCTAssertEqual(session.claudeSessionID, "after-clear")
        XCTAssertNil(manager.usageTrackers[session.id])
        manager.closeAllSessions()
    }

    internal func testShellProjectRecordsNoConversation() async {
        let manager = makeManager()
        let session = manager.createSession(for: remote(RemoteTarget(destination: "dev", command: "")))
        await AsyncWait.drainMainQueue()

        XCTAssertNil(session.claudeSessionID)
        XCTAssertEqual(fake.typedCommands.count, 1)
        XCTAssertTrue(fake.typedCommands.first?.hasSuffix(#""$SHELL" -l'"#) ?? false)
        manager.closeAllSessions()
    }

    internal func testInvalidTargetTypesNothingAndExplains() async {
        let manager = makeManager()
        let session = manager.createSession(for: remote(RemoteTarget(destination: "-oProxyCommand=evil")))
        await AsyncWait.drainMainQueue()

        XCTAssertEqual(fake.typedCommands, [])
        XCTAssertEqual(
            session.errorMessage,
            "Can't open -oProxyCommand=evil: The host can't start with \"-\". Edit the project to fix it."
        )
        manager.closeAllSessions()
    }

    internal func testMissingSSHIsReported() async {
        fake.onPath = []
        let manager = makeManager()
        let session = manager.createSession(for: remote())

        let reported = await AsyncWait.until { session.errorMessage != nil }

        XCTAssertTrue(reported)
        XCTAssertTrue(session.errorMessage?.hasPrefix("'ssh' is not installed") ?? false)
        manager.closeAllSessions()
    }

    internal func testContinueOverrideRunsWithoutAChosenID() async {
        let manager = makeManager()
        let folder = remote()
        let command = LaunchCommandResolver.continueCommand(for: folder.primaryCommand)
        manager.ensureSession(for: folder, commandOverride: command)
        await AsyncWait.drainMainQueue()

        XCTAssertNil(manager.sessions.first?.claudeSessionID)
        XCTAssertTrue(fake.typedCommands.first?.contains("exec claude --continue") ?? false)
        manager.closeAllSessions()
    }

    deinit {
        // Nothing to release.
    }
}
