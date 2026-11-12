@testable import VSVibe
import XCTest

internal final class FolderOrderingTests: XCTestCase {
    private func folder(_ name: String, labels: [UUID] = []) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/Users/x/\(name)"), displayName: name, labelIDs: labels)
    }

    internal func testMoveInsideSectionLeavesOtherProjectsInPlace() {
        let work = UUID()
        // Global order: w1, other, w2 — the section is [w1, w2].
        let folders = [folder("w1", labels: [work]), folder("other"), folder("w2", labels: [work])]
        let sectionIDs = [folders[0].id, folders[2].id]

        // Move w2 (section index 1) to the front of the section.
        let moved = FolderOrdering.move(
            folders: folders,
            groupFolderIDs: sectionIDs,
            fromOffsets: IndexSet(integer: 1),
            toOffset: 0
        )

        XCTAssertEqual(moved.map(\.displayName), ["w2", "other", "w1"])
    }

    internal func testMoveWithinContiguousSection() {
        let folders = [folder("a"), folder("b"), folder("c")]
        let moved = FolderOrdering.move(
            folders: folders,
            groupFolderIDs: folders.map(\.id),
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )
        XCTAssertEqual(moved.map(\.displayName), ["b", "c", "a"])
    }

    internal func testMoveIsNoOpForSingleItemSection() {
        let folders = [folder("a"), folder("b")]
        let moved = FolderOrdering.move(
            folders: folders,
            groupFolderIDs: [folders[0].id],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 1
        )
        XCTAssertEqual(moved.map(\.displayName), ["a", "b"])
    }

    internal func testMoveIgnoresUnknownIDs() {
        let folders = [folder("a"), folder("b")]
        let moved = FolderOrdering.move(
            folders: folders,
            groupFolderIDs: [UUID(), UUID()],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 1
        )
        XCTAssertEqual(moved.map(\.displayName), ["a", "b"])
    }

    deinit {
        // Nothing to release.
    }
}
