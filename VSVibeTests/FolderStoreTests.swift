import XCTest
@testable import VSVibe

@MainActor
final class FolderStoreTests: XCTestCase {

    private var dir: URL!
    private var stateFile: URL!

    override func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir("folderstore")
        stateFile = dir.appendingPathComponent("state.json")
    }

    override func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    private func makeStore() -> FolderStore {
        FolderStore(fileURL: stateFile)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/x/\(name)")
    }

    /// The store saves on a 0.5s debounce; give it room, then read back.
    private func waitForSave() {
        let done = expectation(description: "debounced save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    // MARK: - Projects

    func testAddSkipsDuplicatePaths() {
        let store = makeStore()
        store.add(url: url("a"))
        store.add(url: url("a"))
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertTrue(store.contains(url: url("a")))
    }

    func testCreateProjectWithLabels() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [label.id])
        XCTAssertEqual(entry.labelIDs, [label.id])
    }

    func testCreateProjectDropsUnknownLabelIDs() {
        let store = makeStore()
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [UUID()])
        XCTAssertTrue(entry.labelIDs.isEmpty)
    }

    func testCreateProjectOnExistingPathUpdatesInstead() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.createProject(url: url("api"), name: "API v2", launchCommand: "opencode", labelIDs: [label.id])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].displayName, "API v2")
        XCTAssertEqual(store.folders[0].launchCommand, "opencode")
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
    }

    func testUpdateProjectLeavesLabelsAloneWhenNilPassed() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [label.id])
        store.updateProject(id: entry.id, name: "Renamed", launchCommand: "claude")
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
        XCTAssertEqual(store.folders[0].displayName, "Renamed")
    }

    func testRemoveAndRenameAndSetLaunchCommand() {
        let store = makeStore()
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.rename(id: entry.id, to: "Renamed")
        XCTAssertEqual(store.folders[0].displayName, "Renamed")
        store.setLaunchCommand(id: entry.id, to: "  ")   // ignored
        XCTAssertEqual(store.folders[0].launchCommand, "claude")
        store.setLaunchCommand(id: entry.id, to: "opencode")
        XCTAssertEqual(store.folders[0].launchCommand, "opencode")
        store.remove(id: entry.id)
        XCTAssertTrue(store.folders.isEmpty)
    }

    // MARK: - Label CRUD

    func testCreateLabelTrimsAndAssignsDistinctColors() {
        let store = makeStore()
        let a = store.createLabel(name: "  Work  ")
        let b = store.createLabel(name: "Pet")
        XCTAssertEqual(a?.name, "Work")
        XCTAssertNotEqual(a?.colorHex, b?.colorHex)
        XCTAssertEqual(store.labels.count, 2)
    }

    func testCreateLabelRejectsBlankName() {
        let store = makeStore()
        XCTAssertNil(store.createLabel(name: "   "))
        XCTAssertTrue(store.labels.isEmpty)
    }

    func testCreateLabelReturnsExistingOnDuplicateName() {
        let store = makeStore()
        let first = store.createLabel(name: "Work")!
        let again = store.createLabel(name: "work")
        XCTAssertEqual(again?.id, first.id)
        XCTAssertEqual(store.labels.count, 1)
    }

    func testUpdateLabel() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        store.updateLabel(id: label.id, name: "Clients", colorHex: "22c55e", symbolName: "leaf.fill")
        XCTAssertEqual(store.label(id: label.id)?.name, "Clients")
        XCTAssertEqual(store.label(id: label.id)?.colorHex, "#22C55E")
        XCTAssertEqual(store.label(id: label.id)?.symbolName, "leaf.fill")
    }

    func testUpdateLabelIgnoresBlankNameAndBadColor() {
        let store = makeStore()
        let label = store.createLabel(name: "Work", colorHex: "#3B82F6")!
        store.updateLabel(id: label.id, name: "  ", colorHex: "nope", symbolName: "")
        XCTAssertEqual(store.label(id: label.id)?.name, "Work")
        XCTAssertEqual(store.label(id: label.id)?.colorHex, "#3B82F6")
        XCTAssertEqual(store.label(id: label.id)?.symbolName, LabelPalette.defaultSymbol)
    }

    func testDeleteLabelDetachesItFromProjectsButKeepsThem() {
        let store = makeStore()
        let work = store.createLabel(name: "Work")!
        let pet = store.createLabel(name: "Pet")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude",
                                        labelIDs: [work.id, pet.id])

        store.deleteLabel(id: work.id)

        XCTAssertEqual(store.labels.map(\.name), ["Pet"])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first(where: { $0.id == entry.id })?.labelIDs, [pet.id])
    }

    func testDeleteUnknownLabelIsNoOp() {
        let store = makeStore()
        store.createLabel(name: "Work")
        store.deleteLabel(id: UUID())
        XCTAssertEqual(store.labels.count, 1)
    }

    func testMoveLabelsReordersSections() {
        let store = makeStore()
        store.createLabel(name: "A")
        store.createLabel(name: "B")
        store.createLabel(name: "C")
        store.moveLabels(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.labels.map(\.name), ["C", "A", "B"])
    }

    func testCollapsedStateToggles() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        XCTAssertFalse(store.label(id: label.id)!.isCollapsed)
        store.setLabelCollapsed(id: label.id, true)
        XCTAssertTrue(store.label(id: label.id)!.isCollapsed)
        store.setUngroupedCollapsed(true)
        XCTAssertTrue(store.ungroupedCollapsed)
        store.setUngroupedCollapsed(true) // no-op branch
        XCTAssertTrue(store.ungroupedCollapsed)
    }

    // MARK: - Assignment

    func testToggleLabelAddsThenRemoves() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.toggleLabel(label.id, for: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
        store.toggleLabel(label.id, for: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    func testAddLabelIgnoresUnknownLabelAndDuplicates() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.addLabel(UUID(), to: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
        store.addLabel(label.id, to: entry.id)
        store.addLabel(label.id, to: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
    }

    func testRemoveLabelNotPresentIsNoOp() {
        let store = makeStore()
        let label = store.createLabel(name: "Work")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.removeLabel(label.id, from: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    func testSetLabelsDedupesAndDropsUnknown() {
        let store = makeStore()
        let a = store.createLabel(name: "A")!
        let b = store.createLabel(name: "B")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.setLabels([a.id, a.id, UUID(), b.id], for: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [a.id, b.id])

        store.setLabels([], for: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    func testLabelsForFolderResolvesInAssignmentOrder() {
        let store = makeStore()
        let a = store.createLabel(name: "A")!
        let b = store.createLabel(name: "B")!
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude",
                                        labelIDs: [b.id, a.id])
        XCTAssertEqual(store.labels(for: entry).map(\.name), ["B", "A"])
    }

    // MARK: - Grouping / ordering

    func testSidebarGroupsReflectStoreContents() {
        let store = makeStore()
        let work = store.createLabel(name: "Work")!
        store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [work.id])
        store.createProject(url: url("scratch"), name: "scratch", launchCommand: "claude")

        XCTAssertEqual(store.sidebarGroups.map(\.title), ["Work", "Ungrouped"])
        XCTAssertEqual(store.sidebarGroups[0].folders.map(\.displayName), ["API"])
    }

    func testMoveInGroupReordersGlobally() {
        let store = makeStore()
        let work = store.createLabel(name: "Work")!
        let w1 = store.createProject(url: url("w1"), name: "w1", launchCommand: "claude", labelIDs: [work.id])
        store.createProject(url: url("other"), name: "other", launchCommand: "claude")
        let w2 = store.createProject(url: url("w2"), name: "w2", launchCommand: "claude", labelIDs: [work.id])

        store.move(inGroupWithFolderIDs: [w1.id, w2.id], fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(store.folders.map(\.displayName), ["w2", "other", "w1"])
        XCTAssertEqual(store.sidebarGroups[0].folders.map(\.displayName), ["w2", "w1"])
    }

    func testTopLevelMoveStillWorks() {
        let store = makeStore()
        store.createProject(url: url("a"), name: "a", launchCommand: "claude")
        store.createProject(url: url("b"), name: "b", launchCommand: "claude")
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(store.folders.map(\.displayName), ["b", "a"])
    }

    // MARK: - Persistence

    func testLabelsAndAssignmentsSurviveReload() {
        let store = makeStore()
        let work = store.createLabel(name: "Work", colorHex: "#22C55E", symbolName: "hammer.fill")!
        store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [work.id])
        store.setLabelCollapsed(id: work.id, true)
        store.setUngroupedCollapsed(true)
        waitForSave()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.labels.count, 1)
        XCTAssertEqual(reloaded.labels[0].name, "Work")
        XCTAssertEqual(reloaded.labels[0].colorHex, "#22C55E")
        XCTAssertEqual(reloaded.labels[0].symbolName, "hammer.fill")
        XCTAssertTrue(reloaded.labels[0].isCollapsed)
        XCTAssertTrue(reloaded.ungroupedCollapsed)
        XCTAssertEqual(reloaded.folders[0].labelIDs, [work.id])
    }

    /// A legacy v1 state file must load, with every project unlabelled.
    func testLoadsVersion1StateFile() {
        let json = """
        {"version":1,"folders":[{"id":"\(UUID().uuidString)","url":"file:///Users/x/a/",\
        "displayName":"a","launchCommand":"claude","addedAt":"2026-01-01T00:00:00Z"}]}
        """
        TestSupport.write(json, to: stateFile)

        let store = makeStore()
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
        XCTAssertEqual(store.sidebarGroups.map(\.title), ["Shortcuts"])
    }

    /// Label ids left behind by an out-of-band edit are dropped on load.
    func testLoadDropsDanglingLabelIDs() {
        let store = makeStore()
        let work = store.createLabel(name: "Work")!
        store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [work.id])
        waitForSave()

        // Rewrite the file with the label removed but the assignment kept.
        var obj = try! JSONSerialization.jsonObject(with: Data(contentsOf: stateFile)) as! [String: Any]
        obj["labels"] = []
        TestSupport.write(String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self),
                          to: stateFile)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.folders[0].labelIDs.isEmpty)
        XCTAssertEqual(reloaded.sidebarGroups.map(\.title), ["Shortcuts"])
    }

    func testMissingStateFileStartsEmpty() {
        let store = FolderStore(fileURL: dir.appendingPathComponent("nope.json"))
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
    }

    func testCorruptStateFileStartsEmpty() {
        TestSupport.write("{ not json", to: stateFile)
        let store = makeStore()
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
    }
}
