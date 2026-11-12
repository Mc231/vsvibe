@testable import VSVibe
import XCTest

final class GitReviewTests: XCTestCase {
    private var directories: [URL] = []
    override func tearDown() {
        directories.forEach(TestSupport.remove)
        super.tearDown()
    }
    private func repo() -> URL {
        let url = TestSupport.makeRepo()
        directories.append(url)
        return url
    }

    func testBranchesIncludesRemoteButNotSymbolicRemoteHead() throws {
        let url = repo()
        TestSupport.git(["branch", "feature/test"], in: url)
        TestSupport.git(["update-ref", "refs/remotes/origin/main", "HEAD"], in: url)
        TestSupport.git(["symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main"], in: url)
        let branches = try GitReview.branches(in: url)
        XCTAssertTrue(branches.contains(GitReviewBranch(id: "refs/heads/feature/test", name: "feature/test")))
        XCTAssertTrue(branches.contains(GitReviewBranch(id: "refs/remotes/origin/main", name: "remote: origin/main")))
        XCTAssertFalse(branches.contains { $0.id == "refs/remotes/origin/HEAD" })
        XCTAssertEqual(branches.last?.id, "HEAD")
    }

    func testComparisonModesAndReadOnlySnapshot() throws {
        let url = repo()
        TestSupport.git(["switch", "-c", "feature"], in: url)
        TestSupport.write("feature\n", to: url.appendingPathComponent("feature.txt"))
        TestSupport.git(["add", "."], in: url)
        TestSupport.git(["commit", "-m", "feature"], in: url)
        TestSupport.git(["switch", "main"], in: url)
        TestSupport.write("main\n", to: url.appendingPathComponent("main.txt"))
        TestSupport.git(["add", "."], in: url)
        TestSupport.git(["commit", "-m", "main"], in: url)
        TestSupport.write("uncommitted\n", to: url.appendingPathComponent("README.md"))

        let review = try GitReview.compare(in: url, base: "main", target: "feature", mode: .mergeBase)
        XCTAssertEqual(review.files.map(\.path), ["feature.txt"])
        XCTAssertEqual(review.files.first?.added, 1)
        let tips = try GitReview.compare(in: url, base: "main", target: "feature", mode: .tips)
        XCTAssertEqual(tips.files.map(\.status), ["A", "D"])
        TestSupport.git(["branch", "-f", "feature", "main"], in: url)
        let patch = try GitReview.patch(in: url, comparison: review, file: XCTUnwrap(review.files.first))
        XCTAssertTrue(patch.contains("+feature"))
        XCTAssertEqual(GitInfo.currentBranch(forFolder: url), "main")
        XCTAssertEqual(try String(contentsOf: url.appendingPathComponent("README.md")), "uncommitted\n")
        XCTAssertTrue(try GitReview.compare(in: url, base: "main", target: "main", mode: .tips).files.isEmpty)
    }

    func testUnusualPathsBinaryDeletionAndLiteralPathspec() throws {
        let url = repo()
        TestSupport.git(["branch", "base"], in: url)
        let paths = ["space name.txt", "tab\tname.txt", "line\nbreak.txt", ":(glob)*", "unicode-ї.txt"]
        for path in paths { TestSupport.write("new\n", to: url.appendingPathComponent(path)) }
        try Data([0, 1, 2, 0, 4]).write(to: url.appendingPathComponent("binary.dat"))
        TestSupport.git(["rm", "README.md"], in: url)
        TestSupport.git(["add", "."], in: url)
        TestSupport.git(["commit", "-m", "changes"], in: url)
        let result = try GitReview.compare(in: url, base: "base", target: "main", mode: .tips)
        XCTAssertEqual(Set(result.files.map(\.path)), Set(paths + ["binary.dat", "README.md"]))
        XCTAssertTrue(try XCTUnwrap(result.files.first { $0.path == "binary.dat" }).isBinary)
        XCTAssertEqual(result.files.first { $0.path == "README.md" }?.removed, 1)
        let literal = try XCTUnwrap(result.files.first { $0.path == ":(glob)*" })
        let patch = try GitReview.patch(in: url, comparison: result, file: literal)
        XCTAssertTrue(patch.contains("+new"))
        XCTAssertFalse(patch.contains("space name.txt"))
    }

    func testInvalidRepositoryEmptyRepositoryAndInvalidRef() throws {
        let url = TestSupport.makeTempDir()
        directories.append(url)
        XCTAssertThrowsError(try GitReview.branches(in: url))
        TestSupport.git(["init", "-b", "main"], in: url)
        XCTAssertThrowsError(try GitReview.branches(in: url))
        let valid = repo()
        XCTAssertThrowsError(try GitReview.compare(in: valid, base: "--help", target: "main", mode: .tips))
        XCTAssertThrowsError(try GitReview.patch(in: valid,
                                               comparison: GitComparison(baseCommit: "missing", targetCommit: "HEAD", files: []),
                                               file: GitChangedFile(path: "README.md", status: "M", added: 0, removed: 0)))
    }

    func testReviewFromSubdirectoryAndWorktree() throws {
        let url = repo()
        TestSupport.git(["branch", "base"], in: url)
        let subdirectory = url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        TestSupport.write("nested change\n", to: subdirectory.appendingPathComponent("file.txt"))
        TestSupport.git(["add", "."], in: url)
        TestSupport.git(["commit", "-m", "nested"], in: url)
        let result = try GitReview.compare(in: subdirectory, base: "base", target: "main", mode: .tips)
        XCTAssertEqual(result.files.first?.path, "nested/file.txt")
        XCTAssertTrue(try GitReview.patch(in: subdirectory, comparison: result, file: XCTUnwrap(result.files.first))
            .contains("+nested change"))
        let worktree = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        directories.append(worktree)
        TestSupport.git(["worktree", "add", "--detach", worktree.path, "HEAD"], in: url)
        XCTAssertEqual(try GitReview.compare(in: worktree, base: "base", target: "HEAD", mode: .tips).files, result.files)
    }

    func testParserHandlesMalformedRecordsAndMissingCounts() {
        XCTAssertTrue(GitReview.parseFiles(names: "", counts: "invalid").isEmpty)
        let files = GitReview.parseFiles(names: "M\0file\0incomplete", counts: "bad\0")
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
    }

    func testRunnerDrainsLargeOutputAndErrorsAndBoundsPreview() throws {
        let url = repo()
        let result = try GitCommand.run(["-c", "yes out | head -c 200000; yes err | head -c 200000 >&2; exit 7"],
                                        in: url, outputLimit: 1_000, executable: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertEqual(result.stdout.utf8.count, 1_000)
        XCTAssertEqual(result.stderr.utf8.count, 65_536)
        XCTAssertTrue(result.truncated)
        XCTAssertThrowsError(try GitCommand.run([], in: url, executable: URL(fileURLWithPath: "/not/a/command")))
        let start = Date()
        XCTAssertThrowsError(try GitCommand.run(["-c", "trap '' TERM; while :; do :; done"], in: url,
                                               timeout: 0.1, executable: URL(fileURLWithPath: "/bin/sh")))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testLargePatchIsExplicitlyTruncated() throws {
        let url = repo()
        TestSupport.git(["branch", "base"], in: url)
        TestSupport.write(String(repeating: "a line of text\n", count: 50_000), to: url.appendingPathComponent("large.txt"))
        TestSupport.git(["add", "."], in: url)
        TestSupport.git(["commit", "-m", "large"], in: url)
        let result = try GitReview.compare(in: url, base: "base", target: "main", mode: .tips)
        XCTAssertTrue(try GitReview.patch(in: url, comparison: result, file: XCTUnwrap(result.files.first))
            .contains("Diff preview truncated"))
    }
}
