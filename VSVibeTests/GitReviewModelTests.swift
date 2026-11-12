@testable import VSVibe
import XCTest

internal final class GitReviewModelTests: XCTestCase {
    internal func testChangedFileIdIsPathAndBinaryNeedsBothCounts() {
        let text = GitChangedFile(path: "src/a.swift", status: "M", added: 3, removed: 1)
        XCTAssertEqual(text.id, "src/a.swift")
        XCTAssertFalse(text.isBinary)
        XCTAssertTrue(GitChangedFile(path: "img.png", status: "A", added: nil, removed: nil).isBinary)
        XCTAssertTrue(GitChangedFile(path: "half", status: "M", added: 1, removed: nil).isBinary)
    }

    internal func testComparisonModeIdentityAndLabels() {
        XCTAssertEqual(GitComparisonMode.allCases, [.mergeBase, .tips])
        XCTAssertEqual(GitComparisonMode.mergeBase.id, .mergeBase)
        XCTAssertEqual(GitComparisonMode.tips.id, .tips)
        XCTAssertEqual(GitComparisonMode.mergeBase.rawValue, "Since common ancestor")
        XCTAssertEqual(GitComparisonMode.tips.rawValue, "Branch tips")
    }

    internal func testReviewBranchEquality() {
        let branch = GitReviewBranch(id: "refs/heads/main", name: "main")
        XCTAssertEqual(branch, GitReviewBranch(id: "refs/heads/main", name: "main"))
        XCTAssertNotEqual(branch, GitReviewBranch(id: "refs/remotes/origin/main", name: "main"))
    }

    deinit {
        // No shared state to release.
    }
}
