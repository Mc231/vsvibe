@testable import VSVibe
import XCTest

/// `FolderStore` label CRUD and label-to-project assignment.
@MainActor
internal final class FolderStoreLabelTests: XCTestCase {
    private var dir = TestSupport.placeholderURL

    override internal func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir("folderstore")
    }

    override internal func tearDown() {
        TestSupport.remove(dir)
        super.tearDown()
    }

    private func makeStore() -> FolderStore {
        FolderStore(fileURL: dir.appendingPathComponent("state.json"))
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/x/\(name)")
    }

    // MARK: - Label CRUD

    internal func testCreateLabelTrimsAndAssignsDistinctColors() {
        let store = makeStore()
        let work = store.createLabel(name: "  Work  ")
        let pet = store.createLabel(name: "Pet")
        XCTAssertEqual(work?.name, "Work")
        XCTAssertNotEqual(work?.colorHex, pet?.colorHex)
        XCTAssertEqual(store.labels.count, 2)
    }

    internal func testCreateLabelRejectsBlankName() {
        let store = makeStore()
        XCTAssertNil(store.createLabel(name: "   "))
        XCTAssertTrue(store.labels.isEmpty)
    }

    internal func testCreateLabelReturnsExistingOnDuplicateName() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.createLabel(name: "Work"))
        let again = store.createLabel(name: "work")
        XCTAssertEqual(again?.id, first.id)
        XCTAssertEqual(store.labels.count, 1)
    }

    internal func testUpdateLabel() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        store.updateLabel(id: label.id, name: "Clients", colorHex: "22c55e", symbolName: "leaf.fill")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.name, "Clients")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.colorHex, "#22C55E")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.symbolName, "leaf.fill")
    }

    internal func testUpdateLabelIgnoresBlankNameAndBadColor() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work", colorHex: "#3B82F6"))
        store.updateLabel(id: label.id, name: "  ", colorHex: "nope", symbolName: "")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.name, "Work")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.colorHex, "#3B82F6")
        XCTAssertEqual(store.labels.first { $0.id == label.id }?.symbolName, LabelPalette.defaultSymbol)
    }

    internal func testDeleteLabelDetachesItFromProjectsButKeepsThem() throws {
        let store = makeStore()
        let work = try XCTUnwrap(store.createLabel(name: "Work"))
        let pet = try XCTUnwrap(store.createLabel(name: "Pet"))
        let entry = store.createProject(
            url: url("api"),
            name: "API",
            launchCommand: "claude",
            labelIDs: [work.id, pet.id]
        )

        store.deleteLabel(id: work.id)

        XCTAssertEqual(store.labels.map(\.name), ["Pet"])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders.first { $0.id == entry.id }?.labelIDs, [pet.id])
    }

    internal func testDeleteUnknownLabelIsNoOp() {
        let store = makeStore()
        store.createLabel(name: "Work")
        store.deleteLabel(id: UUID())
        XCTAssertEqual(store.labels.count, 1)
    }

    internal func testMoveLabelsReordersSections() {
        let store = makeStore()
        store.createLabel(name: "A")
        store.createLabel(name: "B")
        store.createLabel(name: "C")
        store.moveLabels(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.labels.map(\.name), ["C", "A", "B"])
    }

    internal func testCollapsedStateToggles() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        XCTAssertFalse(try XCTUnwrap(store.labels.first { $0.id == label.id }).isCollapsed)
        store.setLabelCollapsed(id: label.id, true)
        XCTAssertTrue(try XCTUnwrap(store.labels.first { $0.id == label.id }).isCollapsed)
        store.setUngroupedCollapsed(true)
        XCTAssertTrue(store.ungroupedCollapsed)
        store.setUngroupedCollapsed(true) // no-op branch
        XCTAssertTrue(store.ungroupedCollapsed)
    }

    // MARK: - Assignment

    internal func testToggleLabelAddsThenRemoves() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.toggleLabel(label.id, for: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
        store.toggleLabel(label.id, for: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    internal func testAddLabelIgnoresUnknownLabelAndDuplicates() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.addLabel(UUID(), to: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
        store.addLabel(label.id, to: entry.id)
        store.addLabel(label.id, to: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
    }

    internal func testRemoveLabelNotPresentIsNoOp() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.removeLabel(label.id, from: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    internal func testSetLabelsDedupesAndDropsUnknown() throws {
        let store = makeStore()
        let labelA = try XCTUnwrap(store.createLabel(name: "A"))
        let labelB = try XCTUnwrap(store.createLabel(name: "B"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")

        store.setLabels([labelA.id, labelA.id, UUID(), labelB.id], for: entry.id)
        XCTAssertEqual(store.folders[0].labelIDs, [labelA.id, labelB.id])

        store.setLabels([], for: entry.id)
        XCTAssertTrue(store.folders[0].labelIDs.isEmpty)
    }

    internal func testLabelsForFolderResolvesInAssignmentOrder() throws {
        let store = makeStore()
        let labelA = try XCTUnwrap(store.createLabel(name: "A"))
        let labelB = try XCTUnwrap(store.createLabel(name: "B"))
        let entry = store.createProject(
            url: url("api"),
            name: "API",
            launchCommand: "claude",
            labelIDs: [labelB.id, labelA.id]
        )
        XCTAssertEqual(store.labels(for: entry).map(\.name), ["B", "A"])
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
