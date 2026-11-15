@testable import VSVibe
import XCTest

internal final class CommandLocatorTests: XCTestCase {
    private var tempDirs: [URL] = []

    override internal func setUp() {
        super.setUp()
        tempDirs = []
    }

    override internal func tearDown() {
        for dir in tempDirs {
            TestSupport.remove(dir)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    private func makeBinDir() -> URL {
        let dir = TestSupport.makeTempDir("bin")
        tempDirs.append(dir)
        return dir
    }

    @discardableResult
    private func installExecutable(named name: String, in dir: URL, executable: Bool = true) -> URL {
        let url = dir.appendingPathComponent(name)
        TestSupport.write("#!/bin/sh\nexit 0\n", to: url)
        if executable {
            try? FileManager.default.setAttributes(
                [.posixPermissions: Int(0o755)],
                ofItemAtPath: url.path
            )
        }
        return url
    }

    // MARK: - resolveExecutable

    internal func testEmptyCommandIsNotFound() {
        XCTAssertNil(CommandLocator.resolveExecutable("", searchPaths: ["/bin"]))
    }

    internal func testAbsolutePathResolvesDirectly() {
        XCTAssertEqual(CommandLocator.resolveExecutable("/bin/ls", searchPaths: []), "/bin/ls")
        XCTAssertNil(CommandLocator.resolveExecutable("/bin/definitely-not-a-real-binary", searchPaths: []))
    }

    internal func testFindsExecutableInSearchPaths() {
        let dir = makeBinDir()
        let tool = installExecutable(named: "fake-claude", in: dir)
        let resolved = CommandLocator.resolveExecutable("fake-claude", searchPaths: ["/nonexistent", dir.path])
        XCTAssertEqual(resolved, tool.path)
    }

    internal func testSearchOrderPicksFirstMatch() {
        let first = makeBinDir()
        let second = makeBinDir()
        let winner = installExecutable(named: "tool", in: first)
        installExecutable(named: "tool", in: second)
        let resolved = CommandLocator.resolveExecutable("tool", searchPaths: [first.path, second.path])
        XCTAssertEqual(resolved, winner.path)
    }

    internal func testNonExecutableFileIsNotFound() {
        let dir = makeBinDir()
        installExecutable(named: "not-runnable", in: dir, executable: false)
        XCTAssertNil(CommandLocator.resolveExecutable("not-runnable", searchPaths: [dir.path]))
    }

    internal func testMissingCommandIsNotFound() {
        let dir = makeBinDir()
        XCTAssertNil(CommandLocator.resolveExecutable("ghost", searchPaths: [dir.path]))
    }

    internal func testEmptyAndTrailingSlashSearchPaths() {
        let dir = makeBinDir()
        let tool = installExecutable(named: "tool", in: dir)
        let resolved = CommandLocator.resolveExecutable("tool", searchPaths: ["", dir.path + "/"])
        XCTAssertEqual(resolved, tool.path)
    }

    // MARK: - loginShellAvailability

    internal func testInteractiveLoginShellFindsStandardCommand() {
        let shell = FakeShell.make(in: makeBinDir())
        XCTAssertEqual(CommandLocator.loginShellAvailability("ls", shell: shell), .found)
    }

    internal func testInteractiveLoginShellMissesUnknownCommand() {
        let shell = FakeShell.make(in: makeBinDir())
        XCTAssertEqual(
            CommandLocator.loginShellAvailability("definitely-not-a-real-command-xyz", shell: shell),
            .missing
        )
    }

    internal func testUnsafeCommandNamesAreNeverRun() {
        // This shell would report `.found` for anything it was asked about.
        let shell = FakeShell.make(in: makeBinDir(), body: "exit 0")
        for name in ["ls'; echo pwned", "ls; rm -rf x", "$(id)", "a b", "-n", "..", "", "~/bin/x", "a`b`"] {
            XCTAssertEqual(CommandLocator.loginShellAvailability(name, shell: shell), .unknown, name)
        }
    }

    internal func testInvalidShellIsUnknown() {
        XCTAssertEqual(CommandLocator.loginShellAvailability("ls", shell: "/bin/not-a-shell"), .unknown)
    }

    internal func testSlowShellTimesOutAsUnknown() {
        let shell = FakeShell.make(in: makeBinDir(), body: "sleep 10")
        let start = Date()
        XCTAssertEqual(CommandLocator.loginShellAvailability("ls", shell: shell, timeout: 0.3), .unknown)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    deinit {
        // Nothing to release; temp dirs are removed in tearDown.
    }
}
