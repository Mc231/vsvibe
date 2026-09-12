import XCTest
@testable import VSVibe

final class GitInfoTests: XCTestCase {
    private var dirs: [URL] = []

    override func tearDown() {
        dirs.forEach(TestSupport.remove)
        dirs.removeAll()
        super.tearDown()
    }

    private func track(_ url: URL) -> URL { dirs.append(url); return url }

    func testCurrentBranchOnNormalRepo() {
        let repo = track(TestSupport.makeRepo(initialBranch: "main"))
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "main")
    }

    func testCurrentBranchPreservesSlashes() {
        let repo = track(TestSupport.makeRepo())
        TestSupport.git(["switch", "-c", "feature/foo"], in: repo)
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "feature/foo")
    }

    func testDetachedHeadReturnsShortSha() {
        let repo = track(TestSupport.makeRepo())
        let sha = TestSupport.git(["rev-parse", "HEAD"], in: repo).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        TestSupport.git(["checkout", "--detach", "HEAD"], in: repo)
        let branch = GitInfo.currentBranch(forFolder: repo)
        XCTAssertEqual(branch, String(sha.prefix(7)))
        XCTAssertEqual(branch?.count, 7)
    }

    func testNonRepoReturnsNil() {
        let dir = track(TestSupport.makeTempDir())
        XCTAssertNil(GitInfo.headFileURL(forFolder: dir))
        XCTAssertNil(GitInfo.currentBranch(forFolder: dir))
    }

    func testHeadResolvedFromSubdirectory() {
        let repo = track(TestSupport.makeRepo())
        let sub = repo.appendingPathComponent("a/b", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        XCTAssertEqual(GitInfo.currentBranch(forFolder: sub), "main")
    }

    func testWorktreeHeadIndirection() {
        let repo = track(TestSupport.makeRepo())
        let wt = repo.deletingLastPathComponent()
            .appendingPathComponent("wt-\(UUID().uuidString)", isDirectory: true)
        track(wt)
        TestSupport.git(["worktree", "add", wt.path, "-b", "wtbranch"], in: repo)
        // The worktree's `.git` is a file pointing at the gitdir; HEAD must resolve.
        XCTAssertEqual(GitInfo.currentBranch(forFolder: wt), "wtbranch")
    }

    func testLocalBranches() {
        let repo = track(TestSupport.makeRepo(initialBranch: "main"))
        TestSupport.git(["branch", "dev"], in: repo)
        TestSupport.git(["branch", "release/1.0"], in: repo)
        let branches = Set(GitInfo.localBranches(forFolder: repo))
        XCTAssertEqual(branches, ["main", "dev", "release/1.0"])
    }

    func testLocalBranchesEmptyForNonRepo() {
        let dir = track(TestSupport.makeTempDir())
        XCTAssertTrue(GitInfo.localBranches(forFolder: dir).isEmpty)
    }

    func testSwitchBranchSuccess() {
        let repo = track(TestSupport.makeRepo())
        TestSupport.git(["branch", "dev"], in: repo)
        let result = GitInfo.switchBranch("dev", forFolder: repo)
        guard case .success = result else { return XCTFail("expected success") }
        XCTAssertEqual(GitInfo.currentBranch(forFolder: repo), "dev")
    }

    func testSwitchBranchFailureSurfacesMessage() {
        let repo = track(TestSupport.makeRepo())
        let result = GitInfo.switchBranch("does-not-exist", forFolder: repo)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertFalse(error.message.isEmpty)
    }

    func testCollectStatsOnNonRepo() {
        let dir = track(TestSupport.makeTempDir())
        let stats = GitInfo.collectStats(forFolder: dir)
        XCTAssertFalse(stats.isRepo)
        XCTAssertEqual(stats.commitsInWindow, 0)
    }

    func testCollectStatsCommitsAndChurn() {
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
}
