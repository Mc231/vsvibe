import AppKit
import SwiftTerm
@testable import VSVibe
import XCTest

/// Sessions are created through `FakeSessionLauncher`, so no shell is spawned;
/// stores write to a temp directory.
@MainActor
internal final class SessionManagerTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var fake = FakeSessionLauncher()

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("sessions")
        fake = FakeSessionLauncher()
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStats() -> StatsStore {
        StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
    }

    private func makeAliases() -> LaunchAliasStore {
        LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
    }

    private func makeManager(stats: StatsStore? = nil, aliases: LaunchAliasStore? = nil) -> SessionManager {
        SessionManager(
            statsStore: stats ?? makeStats(),
            aliasStore: aliases ?? makeAliases(),
            launcher: fake.launcher
        )
    }

    private func makeFolder(_ name: String, command: String = "ls") -> FolderEntry {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        fake.onPath.insert(LaunchCommandResolver.baseCommand(of: command))
        return FolderEntry(url: url, launchCommand: command)
    }

    private func delegate(of session: TerminalSession) throws -> SessionProcessDelegate {
        try XCTUnwrap(session.terminalView.processDelegate as? SessionProcessDelegate)
    }

    // MARK: - Creation and lookup

    internal func testCreateSessionSpawnsFocusesAndRecordsPane() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let folder = makeFolder("alpha")

        let first = manager.createSession(for: folder)
        let second = manager.createSession(for: folder)

        XCTAssertEqual(manager.sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(manager.focusedSessionID, second.id)
        XCTAssertEqual(fake.spawnedFolders, [folder.url, folder.url])
        XCTAssertEqual(first.title, "alpha")
        XCTAssertTrue(first.isAlive)
        XCTAssertEqual(try delegate(of: first).sessionID, first.id)
        XCTAssertEqual(stats.summary(forFolderURL: folder.url, window: .today).panesOpened, 2)
        manager.closeAllSessions()
    }

    internal func testEnsureSessionCreatesOnlyOnceAndKeepsFocus() {
        let manager = makeManager()
        let alpha = makeFolder("alpha")
        let beta = makeFolder("beta")

        manager.ensureSession(for: alpha)
        manager.ensureSession(for: alpha, commandOverride: "ls -la")
        manager.ensureSession(for: beta)

        XCTAssertEqual(manager.sessions.count, 2)
        XCTAssertTrue(manager.hasSession(forFolder: alpha.id))
        XCTAssertEqual(manager.sessions(forFolder: alpha.id).count, 1)
        XCTAssertEqual(manager.firstSession(forFolder: beta.id)?.folder.id, beta.id)
        XCTAssertEqual(manager.focusedSessionID, manager.firstSession(forFolder: alpha.id)?.id)
        XCTAssertNil(manager.firstSession(forFolder: UUID()))
        XCTAssertFalse(manager.hasSession(forFolder: UUID()))
        manager.closeAllSessions()
    }

    // MARK: - Closing

    internal func testCloseSessionMovesFocusAndRecordsActiveTime() {
        let stats = makeStats()
        let manager = makeManager(stats: stats)
        let folder = makeFolder("alpha")
        let first = manager.createSession(for: folder)
        let second = manager.createSession(for: folder)

        manager.closeSession(id: second.id)

        XCTAssertEqual(manager.sessions.map(\.id), [first.id])
        XCTAssertEqual(manager.focusedSessionID, first.id)
        XCTAssertNil(second.terminalView.processDelegate)
        XCTAssertGreaterThan(stats.summary(forFolderURL: folder.url, window: .today).activeSeconds, 0)

        manager.closeSession(id: UUID())
        XCTAssertEqual(manager.sessions.count, 1)
        manager.closeSession(id: first.id)
        XCTAssertNil(manager.focusedSessionID)
    }

    internal func testClosingAnUnfocusedSessionKeepsFocus() {
        let manager = makeManager()
        let folder = makeFolder("alpha")
        let first = manager.createSession(for: folder)
        let second = manager.createSession(for: folder)
        manager.closeSession(id: first.id)
        XCTAssertEqual(manager.focusedSessionID, second.id)
        manager.closeAllSessions()
    }

    internal func testCloseAllSessionsForFolderLeavesOthers() {
        let manager = makeManager()
        let alpha = makeFolder("alpha")
        let beta = makeFolder("beta")
        manager.createSession(for: alpha)
        manager.createSession(for: alpha)
        let kept = manager.createSession(for: beta)

        manager.closeAllSessions(forFolder: alpha.id)

        XCTAssertEqual(manager.sessions.map(\.id), [kept.id])
        manager.closeAllSessions()
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.focusedSessionID)
    }

    // MARK: - Reload and focus

    internal func testReloadReplacesSessionAndKeepsFocus() {
        let manager = makeManager()
        let folder = makeFolder("alpha")
        let original = manager.createSession(for: folder)

        manager.reload(id: original.id)

        XCTAssertEqual(manager.sessions.count, 1)
        let replacement = manager.sessions[0]
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.folder.id, folder.id)
        XCTAssertEqual(manager.focusedSessionID, replacement.id)

        manager.reload(id: UUID())
        XCTAssertEqual(manager.sessions.map(\.id), [replacement.id])
        manager.closeAllSessions()
    }

    internal func testReloadOfUnfocusedSessionDoesNotStealFocus() {
        let manager = makeManager()
        let folder = makeFolder("alpha")
        let background = manager.createSession(for: folder)
        let focused = manager.createSession(for: folder)

        manager.reload(id: background.id)

        XCTAssertEqual(manager.focusedSessionID, focused.id)
        XCTAssertEqual(manager.sessions.count, 2)
        manager.closeAllSessions()
    }

    internal func testFocusMakesTerminalFirstResponderWhenInWindow() {
        let manager = makeManager()
        let folder = makeFolder("alpha")
        let windowed = manager.createSession(for: folder)
        let detached = manager.createSession(for: folder)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(windowed.terminalView)

        manager.focus(id: windowed.id)
        XCTAssertEqual(manager.focusedSessionID, windowed.id)
        XCTAssertTrue(window.firstResponder === windowed.terminalView)

        manager.focus(id: detached.id)
        XCTAssertEqual(manager.focusedSessionID, detached.id)
        manager.closeAllSessions()
        window.close()
    }

    // MARK: - Process lifecycle

    internal func testProcessTerminationMarksSessionDead() async throws {
        let manager = makeManager()
        let session = manager.createSession(for: makeFolder("alpha"))
        let delegate = try delegate(of: session)

        delegate.sizeChanged(source: session.terminalView, newCols: 80, newRows: 24)
        delegate.setTerminalTitle(source: session.terminalView, title: "zsh")
        delegate.hostCurrentDirectoryUpdate(source: session.terminalView, directory: "/tmp")
        delegate.processTerminated(source: session.terminalView, exitCode: 3)

        let died = await AsyncWait.until { !session.isAlive }
        XCTAssertTrue(died)
        XCTAssertEqual(session.lastExitCode, 3)
        manager.closeAllSessions()
    }

    internal func testTerminationAfterCloseIsIgnored() async throws {
        let manager = makeManager()
        let session = manager.createSession(for: makeFolder("alpha"))
        let delegate = try delegate(of: session)
        manager.closeSession(id: session.id)

        delegate.processTerminated(source: session.terminalView, exitCode: nil)
        await AsyncWait.drainMainQueue()

        XCTAssertTrue(session.isAlive)
        XCTAssertNil(session.lastExitCode)
    }

    internal func testProcessDelegateIsReleasedWhenSessionCloses() {
        weak var released: SessionProcessDelegate?
        autoreleasepool {
            let manager = makeManager()
            let session = manager.createSession(for: makeFolder("alpha"))
            released = session.terminalView.processDelegate as? SessionProcessDelegate
            XCTAssertNotNil(released)
            manager.closeAllSessions()
        }
        XCTAssertNil(released)
    }

    // MARK: - Launch command checks

    internal func testMissingLaunchCommandFlagsSession() async {
        let manager = makeManager()
        var folder = makeFolder("alpha")
        folder.launchCommand = "vsvibe-missing-tool --flag"

        let session = manager.createSession(for: folder)

        let flagged = await AsyncWait.until { session.errorMessage != nil }
        XCTAssertTrue(flagged)
        XCTAssertEqual(
            session.errorMessage,
            "'vsvibe-missing-tool' is not installed — the pane opened a plain shell. "
                + "Install it or edit the project's launch command."
        )
        manager.closeAllSessions()
    }

    internal func testCommandFoundByLoginShellIsNotFlagged() async {
        fake = FakeSessionLauncher(loginShellKnows: ["nvm-tool"], loginShellTimesOut: ["slow-rc-tool"])
        let manager = makeManager()
        var folder = makeFolder("alpha")
        folder.launchCommand = "nvm-tool"
        let session = manager.createSession(for: folder)
        folder.launchCommand = "slow-rc-tool"
        let timedOut = manager.createSession(for: folder)
        let onPathFolder = makeFolder("beta", command: "ls")
        let onPath = manager.createSession(for: onPathFolder)
        let blank = manager.createSession(for: FolderEntry(url: onPathFolder.url, launchCommand: "  "))

        await AsyncWait.drainMainQueue(seconds: 0.3)

        XCTAssertNil(session.errorMessage)
        XCTAssertNil(timedOut.errorMessage, "A shell that times out must not warn")
        XCTAssertNil(onPath.errorMessage)
        XCTAssertNil(blank.errorMessage)
        manager.closeAllSessions()
    }

    // MARK: - Trackers

    internal func testUsageTrackingOnlyForAliasesWithConfigDir() throws {
        let aliases = makeAliases()
        try aliases.save(command: "work", configPath: directory.appendingPathComponent("claude-work").path)
        try aliases.save(command: "plain", configPath: "")
        let manager = makeManager(aliases: aliases)

        let tracked = manager.createSession(for: makeFolder("alpha", command: "work --continue"))
        let untracked = manager.createSession(for: makeFolder("beta", command: "plain"))

        XCTAssertNotNil(manager.usageTrackers[tracked.id])
        XCTAssertNil(manager.usageTrackers[untracked.id])
        manager.closeSession(id: tracked.id)
        XCTAssertNil(manager.usageTrackers[tracked.id])
        manager.closeAllSessions()
    }

    internal func testGitBranchIsTrackedForRepoFolders() async {
        let repo = TestSupport.makeRepo(initialBranch: "feature")
        defer { TestSupport.remove(repo) }
        fake.onPath.insert("ls")
        let manager = makeManager()
        let session = manager.createSession(for: FolderEntry(url: repo, launchCommand: "ls"))

        let tracked = await AsyncWait.until { session.gitBranch == "feature" }
        XCTAssertTrue(tracked)
        manager.closeAllSessions()
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
