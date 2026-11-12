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

    // MARK: - loginShellCanFind

    internal func testLoginShellFindsStandardCommand() {
        XCTAssertTrue(CommandLocator.loginShellCanFind("ls", shell: "/bin/sh"))
    }

    internal func testLoginShellMissesUnknownCommand() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("definitely-not-a-real-command-xyz", shell: "/bin/sh"))
    }

    internal func testLoginShellRejectsQuoteInCommand() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("ls'; echo pwned", shell: "/bin/sh"))
    }

    internal func testLoginShellHandlesInvalidShell() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("ls", shell: "/bin/not-a-shell"))
    }

    deinit {
        // Nothing to release; temp dirs are removed in tearDown.
    }
}
