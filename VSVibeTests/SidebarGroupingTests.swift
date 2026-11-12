@testable import VSVibe
import XCTest

internal final class SidebarGroupingTests: XCTestCase {
    private func folder(_ name: String, labels: [UUID] = []) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/Users/x/\(name)"), displayName: name, labelIDs: labels)
    }

    internal func testNoLabelsProducesSingleShortcutsSection() {
        let groups = SidebarGrouping.groups(folders: [folder("a"), folder("b")], labels: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups[0].label)
        XCTAssertEqual(groups[0].title, "Shortcuts")
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["a", "b"])
        XCTAssertEqual(groups[0].id, SidebarGroup.ungroupedID)
    }

    internal func testEmptyStateStillShowsShortcutsSection() {
        let groups = SidebarGrouping.groups(folders: [], labels: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].folders.isEmpty)
    }

    internal func testGroupsByLabelInLabelOrderWithUngroupedLast() {
        let work = ProjectLabel(name: "Work")
        let pet = ProjectLabel(name: "Pet")
        let folders = [
            folder("api", labels: [work.id]),
            folder("scratch"),
            folder("vsvibe", labels: [pet.id])
        ]

        let groups = SidebarGrouping.groups(folders: folders, labels: [work, pet])

        XCTAssertEqual(groups.map(\.title), ["Work", "Pet", "Ungrouped"])
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["api"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["vsvibe"])
        XCTAssertEqual(groups[2].folders.map(\.displayName), ["scratch"])
    }

    internal func testProjectWithSeveralLabelsAppearsInEachSection() {
        let work = ProjectLabel(name: "Work")
        let swift = ProjectLabel(name: "Swift")
        let groups = SidebarGrouping.groups(
            folders: [folder("dashboard", labels: [work.id, swift.id])],
            labels: [work, swift]
        )
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["dashboard"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["dashboard"])
        // Fully labelled, so no trailing bucket.
        XCTAssertEqual(groups.count, 2)
    }

    internal func testFoldersKeepGlobalOrderInsideSection() {
        let work = ProjectLabel(name: "Work")
        let folders = [
            folder("c", labels: [work.id]),
            folder("a", labels: [work.id]),
            folder("b", labels: [work.id])
        ]
        let groups = SidebarGrouping.groups(folders: folders, labels: [work])
        XCTAssertEqual(groups[0].folders.map(\.displayName), ["c", "a", "b"])
    }

    internal func testEmptyLabelSectionIsStillListed() {
        let empty = ProjectLabel(name: "Empty")
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [empty])
        XCTAssertEqual(groups.map(\.title), ["Empty", "Ungrouped"])
        XCTAssertTrue(groups[0].folders.isEmpty)
    }

    internal func testUngroupedSectionHiddenWhenEmptyAndLabelsExist() {
        let work = ProjectLabel(name: "Work")
        let groups = SidebarGrouping.groups(folders: [folder("api", labels: [work.id])], labels: [work])
        XCTAssertEqual(groups.map(\.title), ["Work"])
    }

    internal func testDanglingLabelIDFallsBackToUngrouped() {
        let known = ProjectLabel(name: "Work")
        let ghost = UUID()
        let groups = SidebarGrouping.groups(folders: [folder("orphan", labels: [ghost])], labels: [known])
        XCTAssertEqual(groups.map(\.title), ["Work", "Ungrouped"])
        XCTAssertEqual(groups[1].folders.map(\.displayName), ["orphan"])
    }

    internal func testCollapsedStateFlowsFromLabelAndParameter() {
        let work = ProjectLabel(name: "Work", isCollapsed: true)
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [work], ungroupedCollapsed: true)
        XCTAssertTrue(groups[0].isCollapsed)
        XCTAssertTrue(groups[1].isCollapsed)
        XCTAssertTrue(groups[1].isUngrouped)
    }

    internal func testGroupIDsAreStable() {
        let work = ProjectLabel(name: "Work")
        let groups = SidebarGrouping.groups(folders: [folder("a")], labels: [work])
        XCTAssertEqual(groups[0].id, work.id.uuidString)
        XCTAssertEqual(groups[1].id, SidebarGroup.ungroupedID)
    }

    deinit {
        // Nothing to release.
    }
}
