import XCTest
@testable import VSVibe

final class CommandLocatorTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { TestSupport.remove(dir) }
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
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: url.path
            )
        }
        return url
    }

    // MARK: - resolveExecutable

    func testEmptyCommandIsNotFound() {
        XCTAssertNil(CommandLocator.resolveExecutable("", searchPaths: ["/bin"]))
    }

    func testAbsolutePathResolvesDirectly() {
        XCTAssertEqual(CommandLocator.resolveExecutable("/bin/ls", searchPaths: []), "/bin/ls")
        XCTAssertNil(CommandLocator.resolveExecutable("/bin/definitely-not-a-real-binary", searchPaths: []))
    }

    func testFindsExecutableInSearchPaths() {
        let dir = makeBinDir()
        let tool = installExecutable(named: "fake-claude", in: dir)
        let resolved = CommandLocator.resolveExecutable("fake-claude", searchPaths: ["/nonexistent", dir.path])
        XCTAssertEqual(resolved, tool.path)
    }

    func testSearchOrderPicksFirstMatch() {
        let first = makeBinDir()
        let second = makeBinDir()
        let winner = installExecutable(named: "tool", in: first)
        installExecutable(named: "tool", in: second)
        let resolved = CommandLocator.resolveExecutable("tool", searchPaths: [first.path, second.path])
        XCTAssertEqual(resolved, winner.path)
    }

    func testNonExecutableFileIsNotFound() {
        let dir = makeBinDir()
        installExecutable(named: "not-runnable", in: dir, executable: false)
        XCTAssertNil(CommandLocator.resolveExecutable("not-runnable", searchPaths: [dir.path]))
    }

    func testMissingCommandIsNotFound() {
        let dir = makeBinDir()
        XCTAssertNil(CommandLocator.resolveExecutable("ghost", searchPaths: [dir.path]))
    }

    func testEmptyAndTrailingSlashSearchPaths() {
        let dir = makeBinDir()
        let tool = installExecutable(named: "tool", in: dir)
        let resolved = CommandLocator.resolveExecutable("tool", searchPaths: ["", dir.path + "/"])
        XCTAssertEqual(resolved, tool.path)
    }

    // MARK: - loginShellCanFind

    func testLoginShellFindsStandardCommand() {
        XCTAssertTrue(CommandLocator.loginShellCanFind("ls", shell: "/bin/sh"))
    }

    func testLoginShellMissesUnknownCommand() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("definitely-not-a-real-command-xyz", shell: "/bin/sh"))
    }

    func testLoginShellRejectsQuoteInCommand() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("ls'; echo pwned", shell: "/bin/sh"))
    }

    func testLoginShellHandlesInvalidShell() {
        XCTAssertFalse(CommandLocator.loginShellCanFind("ls", shell: "/bin/not-a-shell"))
    }
}

final class EnvBuilderSearchPathsTests: XCTestCase {
    func testSearchPathsContainWellKnownDirs() {
        let paths = EnvBuilder.searchPaths()
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
    }

    func testSearchPathsHaveNoDuplicates() {
        let paths = EnvBuilder.searchPaths()
        XCTAssertEqual(paths.count, Set(paths).count)
    }

    func testSearchPathsMatchBuiltPATH() {
        let paths = EnvBuilder.searchPaths()
        let built = EnvBuilder.build()
            .first { $0.hasPrefix("PATH=") }?
            .dropFirst("PATH=".count)
        XCTAssertEqual(String(built ?? ""), paths.joined(separator: ":"))
    }

    func testExtraPathsIncludedInSearchPaths() {
        XCTAssertTrue(EnvBuilder.searchPaths(extraPaths: ["/custom/tool/bin"]).contains("/custom/tool/bin"))
    }
}
