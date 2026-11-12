@testable import VSVibe
import XCTest

final class SidebarGroupingTests: XCTestCase {
    private func folder(_ name: String, labels: [UUID] = []) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/Users/x/\(name)"), displayName: name, labelIDs: labels)
    }

    func testNoLabelsProducesSingleShortcutsSection() {
        let groups = SidebarGrouping.groups(folders: [folder("a"), folder("b")], labels: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].label)
        XCTAssertEqual(groups[0].title, "Shortcuts")
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["a", "b"])
        XCTAssertEqual(groups[0].id, SidebarGroup.ungroupedID)
    }

    func testEmptyStateStillShowsShortcutsSection() {
        let groups = SidebarGrouping.groups(folders: [], labels: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].folders.isEmpty)
    }

    func testGroupsByLabelInLabelOrderWithUngroupedLast() {
        let work = ProjectLabel(name: "Work")
        let pet = ProjectLabel(name: "Pet")
        let folders = [folder("api", labels: [work.id]),
                       folder("scratch"),
                       folder("vsvibe", labels: [pet.id])]

        let groups = SidebarGrouping.groups(folders: folders, labels: [work, pet])

        XCTAssertEqual(groups.map(\.title), ["Work", "Pet", "Ungrouped"])
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["api"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["vsvibe"])
        XCTAssertEqual(groups[2].folders.map(\.displayName), ["scratch"])
    }

    func testProjectWithSeveralLabelsAppearsInEachSection() {
        let work = ProjectLabel(name: "Work")
        let swift = ProjectLabel(name: "Swift")
        let groups = SidebarGrouping.groups(folders: [folder("dashboard", labels: [work.id, swift.id])],
                                            labels: [work, swift])
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["dashboard"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["dashboard"])
        // Fully labelled, so no trailing bucket.
        XCTAssertEqual(groups.count, 2)
    }

    func testFoldersKeepGlobalOrderInsideSection() {
        let work = ProjectLabel(name: "Work")
        let folders = [folder("c", labels: [work.id]),
                       folder("a", labels: [work.id]),
                       folder("b", labels: [work.id])]
        let groups = SidebarGrouping.groups(folders: folders, labels: [work])
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["c", "a", "b"])
    }

    func testEmptyLabelSectionIsStillListed() {
        let empty = ProjectLabel(name: "Empty")
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [empty])
        XCTAssertEqual(groups.map(\.title), ["Empty", "Ungrouped"])
        XCTAssertTrue(groups[0].folders.isEmpty)
    }

    func testUngroupedSectionHiddenWhenEmptyAndLabelsExist() {
        let work = ProjectLabel(name: "Work")
        let groups = SidebarGrouping.groups(folders: [folder("api", labels: [work.id])], labels: [work])
        XCTAssertEqual(groups.map(\.title), ["Work"])
    }

    func testDanglingLabelIDFallsBackToUngrouped() {
        let known = ProjectLabel(name: "Work")
        let ghost = UUID()
        let groups = SidebarGrouping.groups(folders: [folder("orphan", labels: [ghost])], labels: [known])
        XCTAssertEqual(groups.map(\.title), ["Work", "Ungrouped"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["orphan"])
    }

    func testCollapsedStateFlowsFromLabelAndParameter() {
        let work = ProjectLabel(name: "Work", isCollapsed: true)
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [work], ungroupedCollapsed: true)
        XCTAssertTrue(groups[0].isCollapsed)
        XCTAssertTrue(groups[1].isCollapsed)
        XCTAssertTrue(groups[1].isUngrouped)
    }

    func testGroupIDsAreStable() {
        let work = ProjectLabel(name: "Work")
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [work])
        XCTAssertEqual(groups[0].id, work.id.uuidString)
        XCTAssertEqual(groups[1].id, SidebarGroup.ungroupedID)
    }
}

final class FolderOrderingTests: XCTestCase {
    private func folder(_ name: String, labels: [UUID] = []) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/Users/x/\(name)"), displayName: name, labelIDs: labels)
    }

    func testMoveInsideSectionLeavesOtherProjectsInPlace() {
        let work = UUID()
        // Global order: w1, other, w2 — the section is [w1, w2].
        let folders = [folder("w1", labels: [work]), folder("other"), folder("w2", labels: [work])]
        let sectionIDs = [folders[0].id, folders[2].id]

        // Move w2 (section index 1) to the front of the section.
        let moved = FolderOrdering.move(folders: folders,
                                        groupFolderIDs: sectionIDs,
                                        fromOffsets: IndexSet(integer: 1),
                                        toOffset: 0)

        XCTAssertEqual(moved.map(\.displayName), ["w2", "other", "w1"])
    }

    func testMoveWithinContiguousSection() {
        let folders = [folder("a"), folder("b"), folder("c")]
        let moved = FolderOrdering.move(folders: folders,
                                        groupFolderIDs: folders.map(\.id),
                                        fromOffsets: IndexSet(integer: 0),
                                        toOffset: 3)
        XCTAssertEqual(moved.map(\.displayName), ["b", "c", "a"])
    }

    func testMoveIsNoOpForSingleItemSection() {
        let folders = [folder("a"), folder("b")]
        let moved = FolderOrdering.move(folders: folders,
                                        groupFolderIDs: [folders[0].id],
                                        fromOffsets: IndexSet(integer: 0),
                                        toOffset: 1)
        XCTAssertEqual(moved.map(\.displayName), ["a", "b"])
    }

    func testMoveIgnoresUnknownIDs() {
        let folders = [folder("a"), folder("b")]
        let moved = FolderOrdering.move(folders: folders,
                                        groupFolderIDs: [UUID(), UUID()],
                                        fromOffsets: IndexSet(integer: 0),
                                        toOffset: 1)
        XCTAssertEqual(moved.map(\.displayName), ["a", "b"])
    }
}
