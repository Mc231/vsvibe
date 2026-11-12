@testable import VSVibe
import XCTest

internal final class GitInfoTests: XCTestCase {
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

    @discardableResult
    private func track(_ url: URL) -> URL {
        dirs.append(url)
        return url
    }

    internal func testCurrentBranchOnNormalRepo() {
        let repo = track(TestSupport.makeRepo(initialBranch: "main"))
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "main")
    }

    internal func testCurrentBranchPreservesSlashes() {
        let repo = track(TestSupport.makeRepo())
        TestSupport.git(["switch", "-c", "feature/foo"], in: repo)
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "feature/foo")
    }

    internal func testDetachedHeadReturnsShortSha() {
        let repo = track(TestSupport.makeRepo())
        let sha = TestSupport.git(["rev-parse", "HEAD"], in: repo).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        TestSupport.git(["checkout", "--detach", "HEAD"], in: repo)
        let branch = GitInfo.currentBranch(forFolder: repo)
        XCTAssertEqual(branch, String(sha.prefix(7)))
        XCTAssertEqual(branch?.count, 7)
    }

    internal func testNonRepoReturnsNil() {
        let dir = track(TestSupport.makeTempDir())
        XCTAssertNil(GitInfo.headFileURL(forFolder: dir))
        XCTAssertNil(GitInfo.currentBranch(forFolder: dir))
    }

    internal func testRepositorySearchStopsAtFilesystemRoot() {
        // A background expectation makes a regression fail promptly instead of
        // hanging the test runner's main thread like the original bug.
        let completed = expectation(description: "root search terminates")
        DispatchQueue.global(qos: .utility).async {
            XCTAssertNil(GitInfo.headFileURL(forFolder: URL(fileURLWithPath: "/", isDirectory: true)))
            XCTAssertNil(GitInfo.currentBranch(forFolder: URL(fileURLWithPath: "/../..", isDirectory: true)))
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    internal func testHeadResolvedFromSubdirectory() {
        let repo = track(TestSupport.makeRepo())
        let sub = repo.appendingPathComponent("a/b", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(GitInfo.currentBranch(forFolder: sub), "main")
    }

    internal func testEmptyMissingAndNonstandardHead() {
        let repo = track(TestSupport.makeRepo())
        let head = repo.appendingPathComponent(".git/HEAD")
        TestSupport.write("\n", to: head)
        XCTAssertNil(GitInfo.currentBranch(forFolder: repo))
        TestSupport.write("ref: refs/remotes/origin/main\n", to: head)
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "refs/remotes/origin/main")
        try? FileManager.default.removeItem(at: head)
        XCTAssertNil(GitInfo.currentBranch(forFolder: repo))
        let invalid = track(TestSupport.makeTempDir())
        TestSupport.write("not a gitdir\n", to: invalid.appendingPathComponent(".git"))
        XCTAssertNil(GitInfo.headFileURL(forFolder: invalid))
    }

    internal func testWorktreeHeadIndirection() {
        let repo = track(TestSupport.makeRepo())
        let worktree = repo.deletingLastPathComponent()
            .appendingPathComponent("wt-\(UUID().uuidString)", isDirectory: true)
        track(worktree)
        TestSupport.git(["worktree", "add", worktree.path, "-b", "wtbranch"], in: repo)
        // The worktree's `.git` is a file pointing at the gitdir; HEAD must resolve.
        XCTAssertEqual(GitInfo.currentBranch(forFolder: worktree), "wtbranch")
    }

    internal func testLocalBranches() {
        let repo = track(TestSupport.makeRepo(initialBranch: "main"))
        TestSupport.git(["branch", "dev"], in: repo)
        TestSupport.git(["branch", "release/1.0"], in: repo)
        let branches = Set(GitInfo.localBranches(forFolder: repo))
        XCTAssertEqual(branches, ["main", "dev", "release/1.0"])
    }

    internal func testLocalBranchesEmptyForNonRepo() {
        let dir = track(TestSupport.makeTempDir())
        XCTAssertTrue(GitInfo.localBranches(forFolder: dir).isEmpty)
    }

    internal func testSwitchBranchSuccess() {
        let repo = track(TestSupport.makeRepo())
        TestSupport.git(["branch", "dev"], in: repo)
        let result = GitInfo.switchBranch("dev", forFolder: repo)
        guard case .success = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "dev")
    }

    internal func testSwitchBranchFailureSurfacesMessage() {
        let repo = track(TestSupport.makeRepo())
        let result = GitInfo.switchBranch("does-not-exist", forFolder: repo)
        guard case .failure(let error) = result else {
            XCTFail("expected failure")
            return
        }
        XCTAssertFalse(error.message.isEmpty)
    }

    internal func testCollectStatsOnNonRepo() {
        let dir = track(TestSupport.makeTempDir())
        let stats = GitInfo.collectStats(forFolder: dir)
        XCTAssertFalse(stats.isRepo)
        XCTAssertEqual(stats.commitsInWindow, 0)
    }

    internal func testCollectStatsCommitsAndChurn() {
        let repo = track(TestSupport.makeRepo())
        TestSupport.write("line1\nline2\nline3\n", to: repo.appendingPathComponent("file.txt"))
        TestSupport.git(["add", "."], in: repo)
        TestSupport.git(["commit", "-m", "add file"], in: repo)

        let stats = GitInfo.collectStats(forFolder: repo, windowDays: 30)
        XCTAssertTrue(stats.isRepo)
        XCTAssertEqual(stats.currentBranch, "main")
        XCTAssertGreaterThanOrEqual(stats.branchCount, 1)
        XCTAssertEqual(stats.commitsInWindow, 2) // init + add file
        XCTAssertGreaterThanOrEqual(stats.linesAdded, 4) // README + 3 lines
        XCTAssertNotNil(stats.lastCommitDate)
        XCTAssertEqual(stats.lastCommitSubject, "add file")
        // No upstream configured.
        XCTAssertNil(stats.ahead)
        XCTAssertNil(stats.behind)
    }

    deinit {
        // Nothing to release; temp dirs are removed in tearDown.
    }
}
