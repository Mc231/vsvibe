@testable import VSVibe
import XCTest

internal final class GitInfoEdgeCaseTests: XCTestCase {
    private var dirs: [URL] = []

    override internal func setUp() {
        super.setUp()
        dirs = []
    }

    override internal func tearDown() {
        dirs.forEach(TestSupport.remove)
        dirs.removeAll()
        super.tearDown()
    }

    internal func testGitErrorMessages() {
        XCTAssertEqual(GitInfo.GitError.launchFailed.message, "Couldn't run git.")
        XCTAssertEqual(GitInfo.GitError.failed("boom").message, "boom")
    }

    internal func testDotGitFileWithoutGitdirIsNotARepo() throws {
        let dir = track(TestSupport.makeTempDir())
        try "not a pointer\n".write(to: dir.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertNil(GitInfo.headFileURL(forFolder: dir))
        XCTAssertNil(GitInfo.currentBranch(forFolder: dir))
    }

    internal func testUnreadableDotGitFileIsNotARepo() throws {
        let dir = track(TestSupport.makeTempDir())
        // Invalid UTF-8 cannot be read as a `gitdir:` pointer.
        try Data([0xFF, 0xFE, 0x00]).write(to: dir.appendingPathComponent(".git"))
        XCTAssertNil(GitInfo.headFileURL(forFolder: dir))
    }

    internal func testSwitchBranchInMissingFolderIsLaunchFailure() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("vsvibe-missing-\(UUID().uuidString)", isDirectory: true)
        let result = GitInfo.switchBranch("main", forFolder: missing)
        guard case .failure(let error) = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error.message, GitInfo.GitError.launchFailed.message)
    }

    internal func testCollectStatsReportsAheadAndBehindUpstream() {
        let origin = track(TestSupport.makeRepo())
        let parent = track(TestSupport.makeTempDir("clone-parent"))
        let clone = parent.appendingPathComponent("clone", isDirectory: true)
        XCTAssertEqual(TestSupport.git(["clone", origin.path, clone.path], in: parent).code, 0)

        commit(file: "local.txt", message: "local work", in: clone)
        commit(file: "upstream1.txt", message: "upstream 1", in: origin)
        commit(file: "upstream2.txt", message: "upstream 2", in: origin)
        XCTAssertEqual(TestSupport.git(["fetch"], in: clone).code, 0)

        let stats = GitInfo.collectStats(forFolder: clone)
        XCTAssertEqual(stats.windowDays, GitInfo.defaultStatsWindowDays)
        XCTAssertEqual(stats.ahead, 1)
        XCTAssertEqual(stats.behind, 2)
        XCTAssertEqual(stats.lastCommitSubject, "local work")
        XCTAssertEqual(stats.filesTouched, 2) // README.md + local.txt
    }

    internal func testGitStatsDefaults() {
        let stats = GitStats()
        XCTAssertFalse(stats.isRepo)
        XCTAssertNil(stats.currentBranch)
        XCTAssertNil(stats.ahead)
        XCTAssertNil(stats.behind)
        XCTAssertEqual(stats.windowDays, 30)
        XCTAssertEqual(stats.windowDays, GitInfo.defaultStatsWindowDays)
    }

    private func track(_ url: URL) -> URL {
        dirs.append(url)
        return url
    }

    private func commit(file: String, message: String, in repo: URL) {
        TestSupport.write("\(message)\n", to: repo.appendingPathComponent(file))
        TestSupport.git(["add", "."], in: repo)
        TestSupport.git(["commit", "-m", message], in: repo)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
