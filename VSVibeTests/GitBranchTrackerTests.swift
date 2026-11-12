@testable import VSVibe
import XCTest

@MainActor
internal final class GitBranchTrackerTests: XCTestCase {
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

    internal func testFirstTickReportsEvenWhenBranchIsNil() {
        var reported: [String?] = []
        let tracker = GitBranchTracker(
            folderURL: URL(fileURLWithPath: "/tmp"),
            branchReader: { _ in nil },
            onUpdate: { reported.append($0) }
        )
        tracker.tick()
        XCTAssertEqual(reported, [nil])
    }

    internal func testTicksReportOnlyChanges() {
        var branches: [String?] = ["main", "main", "feature", nil, nil, "main"]
        var reported: [String?] = []
        let tracker = GitBranchTracker(
            folderURL: URL(fileURLWithPath: "/tmp"),
            branchReader: { _ in branches.removeFirst() },
            onUpdate: { reported.append($0) }
        )
        for _ in 0..<6 {
            tracker.tick()
        }
        XCTAssertEqual(reported, ["main", "feature", nil, "main"])
        XCTAssertTrue(branches.isEmpty)
    }

    internal func testReaderReceivesFolderURL() {
        let folder = URL(fileURLWithPath: "/tmp/some-project")
        var seen: [URL] = []
        let tracker = GitBranchTracker(
            folderURL: folder,
            branchReader: { url in
                seen.append(url)
                return "main"
            },
            onUpdate: { _ in
                // Only the reader input matters here.
            }
        )
        tracker.tick()
        XCTAssertEqual(seen, [folder])
    }

    internal func testDefaultReaderParsesHeadFile() throws {
        let folder = try makeFakeRepo(head: "ref: refs/heads/develop\n")
        var reported: [String?] = []
        let tracker = GitBranchTracker(folderURL: folder) { reported.append($0) }
        tracker.tick()
        XCTAssertEqual(reported, ["develop"])
        XCTAssertEqual(GitBranchTracker.defaultPollInterval, 2.0)
    }

    internal func testStartPollsImmediatelyAndPicksUpSwitches() async throws {
        let folder = try makeFakeRepo(head: "ref: refs/heads/main\n")
        let sawMain = expectation(description: "first poll reports main")
        let sawOther = expectation(description: "later poll reports the switch")
        var reported: [String?] = []
        let tracker = GitBranchTracker(folderURL: folder, pollInterval: 0.05) { branch in
            reported.append(branch)
            if branch == "main" {
                sawMain.fulfill()
            } else if branch == "other" {
                sawOther.fulfill()
            }
        }
        XCTAssertFalse(tracker.isRunning)
        tracker.start()
        XCTAssertTrue(tracker.isRunning)
        await fulfillment(of: [sawMain], timeout: 5)

        try "ref: refs/heads/other\n".write(
            to: folder.appendingPathComponent(".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        await fulfillment(of: [sawOther], timeout: 5)
        tracker.stop()
        XCTAssertFalse(tracker.isRunning)
        XCTAssertEqual(reported, ["main", "other"])
    }

    internal func testRestartReplacesTimer() async {
        let polled = expectation(description: "polled after restart")
        polled.assertForOverFulfill = false
        let tracker = GitBranchTracker(
            folderURL: URL(fileURLWithPath: "/tmp"),
            pollInterval: 0.05,
            branchReader: { _ in "main" },
            onUpdate: { _ in polled.fulfill() }
        )
        tracker.start()
        tracker.start()
        XCTAssertTrue(tracker.isRunning)
        await fulfillment(of: [polled], timeout: 5)
        tracker.stop()
        XCTAssertFalse(tracker.isRunning)
    }

    private func makeFakeRepo(head: String) throws -> URL {
        let folder = TestSupport.makeTempDir("branch-tracker")
        dirs.append(folder)
        let gitDir = folder.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try head.write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        return folder
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
