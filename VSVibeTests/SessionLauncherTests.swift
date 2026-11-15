import AppKit
import SwiftTerm
@testable import VSVibe
import XCTest

@MainActor
internal final class SessionLauncherTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("launcher")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testLiveLauncherConfiguration() {
        let live = SessionLauncher.live
        XCTAssertEqual(live.commandDelay, 0.45, accuracy: 0.0001)
        XCTAssertTrue(live.isOnSearchPath("ls"))
        XCTAssertFalse(live.isOnSearchPath("vsvibe-definitely-missing-tool"))
        // An empty command is rejected before any shell is started.
        XCTAssertEqual(live.loginShellAvailability("", "/bin/sh"), .unknown)
    }

    internal func testMakeTerminalViewIsUnstartedAndUsesAutoLayout() {
        let view = SessionLauncher.live.makeTerminalView()
        XCTAssertFalse(view.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(view.frame.size, NSSize(width: 800, height: 600))
        XCTAssertFalse(view.process.running)
        // Terminating or typing into a never-started process is a safe no-op.
        view.injectCommand("echo hi")
        view.process.terminate()
        XCTAssertFalse(view.process.running)
    }

    internal func testLiveSpawnStartsAShellInTheFolder() {
        let view = SessionLauncher.makeTerminalView()
        SessionLauncher.live.spawnShell(view, directory, UUID())
        XCTAssertTrue(view.process.running)
        view.process.terminate()
        XCTAssertFalse(view.process.running)
    }

    internal func testManagerDefaultsToLiveLauncher() {
        let stats = StatsStore(fileURL: directory.appendingPathComponent("stats.json")) { [] }
        let aliases = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        let manager = SessionManager(statsStore: stats, aliasStore: aliases)
        XCTAssertTrue(manager.sessions.isEmpty)
        XCTAssertNil(manager.focusedSessionID)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
