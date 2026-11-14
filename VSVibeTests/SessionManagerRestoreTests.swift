@testable import VSVibe
import XCTest

/// `SessionManager`'s side of session restore: pane ids exported to the shell,
/// the persisted snapshot and reopening a pane with a resume command.
@MainActor
internal final class SessionManagerRestoreTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var fake = FakeSessionLauncher()

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("sessions-restore")
        fake = FakeSessionLauncher()
        fake.onPath = ["ls", "claude"]
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func makeManager() -> SessionManager {
        SessionManager(
            statsStore: StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] },
            aliasStore: LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json")),
            launcher: fake.launcher
        )
    }

    private func makeFolder(_ name: String) -> FolderEntry {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FolderEntry(url: url, launchCommand: "ls")
    }

    internal func testShellGetsThePaneID() {
        let manager = makeManager()
        let session = manager.createSession(for: makeFolder("alpha"))
        XCTAssertEqual(fake.spawnedPaneIDs, [session.id])
        manager.closeAllSessions()
    }

    internal func testSnapshotKeepsOrderFocusAndClaudeSessionIDs() {
        let manager = makeManager()
        let alpha = makeFolder("alpha")
        let beta = makeFolder("beta")
        let first = manager.createSession(for: alpha)
        manager.createSession(for: beta)
        manager.createSession(for: alpha)
        first.claudeSessionID = "conv-1"
        manager.focus(id: first.id)

        let snapshot = manager.snapshot

        XCTAssertEqual(snapshot.version, SessionSnapshot.currentVersion)
        XCTAssertEqual(snapshot.panes.map(\.folderID), [alpha.id, beta.id, alpha.id])
        XCTAssertEqual(snapshot.panes.map(\.claudeSessionID), ["conv-1", nil, nil])
        XCTAssertEqual(snapshot.focusedIndex, 0)

        manager.closeAllSessions()
        XCTAssertEqual(manager.snapshot, SessionSnapshot(panes: [], focusedIndex: nil))
    }

    internal func testRestoreSessionTypesTheCommandAndCarriesTheID() async {
        let manager = makeManager()
        let folder = makeFolder("alpha")

        let session = manager.restoreSession(for: folder, command: "claude --resume conv-1", claudeSessionID: "conv-1")

        XCTAssertEqual(session.claudeSessionID, "conv-1")
        XCTAssertEqual(manager.sessions.map(\.id), [session.id])
        XCTAssertEqual(fake.spawnedFolders, [folder.url])
        XCTAssertNil(session.errorMessage, "the command's base executable is verified, not the whole line")
        await AsyncWait.drainMainQueue()
        manager.closeAllSessions()
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
