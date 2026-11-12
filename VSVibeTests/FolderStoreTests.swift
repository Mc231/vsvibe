@testable import VSVibe
import XCTest

/// Projects, grouping/ordering and persistence. Label CRUD and assignment live
/// in `FolderStoreLabelTests`.
@MainActor
internal final class FolderStoreTests: XCTestCase {
    private var dir = TestSupport.placeholderURL

    private var stateFile: URL {
        dir.appendingPathComponent("state.json")
    }

    override internal func setUp() {
        super.setUp()
        dir = TestSupport.makeTempDir("folderstore")
    }

    override internal func tearDown() {
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

    internal func testAddSkipsDuplicatePaths() {
        let store = makeStore()
        store.add(url: url("a"))
        store.add(url: url("a"))
        XCTAssertEqual(store.folders.count, 1)
    }

    internal func testCreateProjectWithLabels() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [label.id])
        XCTAssertEqual(entry.labelIDs, [label.id])
    }

    internal func testCreateProjectDropsUnknownLabelIDs() {
        let store = makeStore()
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [UUID()])
        XCTAssertTrue(entry.labelIDs.isEmpty)
    }

    internal func testCreateProjectOnExistingPathUpdatesInstead() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.createProject(url: url("api"), name: "API v2", launchCommand: "opencode", labelIDs: [label.id])
        XCTAssertEqual(store.folders.count, 1)
        XCTAssertEqual(store.folders[0].displayName, "API v2")
        XCTAssertEqual(store.folders[0].launchCommand, "opencode")
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
    }

    internal func testUpdateProjectLeavesLabelsAloneWhenNilPassed() throws {
        let store = makeStore()
        let label = try XCTUnwrap(store.createLabel(name: "Work"))
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [label.id])
        store.updateProject(id: entry.id, name: "Renamed", launchCommand: "claude")
        XCTAssertEqual(store.folders[0].labelIDs, [label.id])
        XCTAssertEqual(store.folders[0].displayName, "Renamed")
    }

    internal func testRemove() {
        let store = makeStore()
        let entry = store.createProject(url: url("api"), name: "API", launchCommand: "claude")
        store.remove(id: entry.id)
        XCTAssertTrue(store.folders.isEmpty)
    }

    // MARK: - Grouping / ordering

    internal func testSidebarGroupsReflectStoreContents() throws {
        let store = makeStore()
        let work = try XCTUnwrap(store.createLabel(name: "Work"))
        store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [work.id])
        store.createProject(url: url("scratch"), name: "scratch", launchCommand: "claude")

        XCTAssertEqual(store.sidebarGroups.map(\.title), ["Work", "Ungrouped"])
        XCTAssertEqual(store.sidebarGroups[0].folders.map(\.displayName), ["API"])
    }

    internal func testMoveInGroupReordersGlobally() throws {
        let store = makeStore()
        let work = try XCTUnwrap(store.createLabel(name: "Work"))
        let first = store.createProject(url: url("w1"), name: "w1", launchCommand: "claude", labelIDs: [work.id])
        store.createProject(url: url("other"), name: "other", launchCommand: "claude")
        let second = store.createProject(url: url("w2"), name: "w2", launchCommand: "claude", labelIDs: [work.id])

        store.move(inGroupWithFolderIDs: [first.id, second.id], fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(store.folders.map(\.displayName), ["w2", "other", "w1"])
        XCTAssertEqual(store.sidebarGroups[0].folders.map(\.displayName), ["w2", "w1"])
    }

    internal func testTopLevelMoveStillWorks() {
        let store = makeStore()
        store.createProject(url: url("a"), name: "a", launchCommand: "claude")
        store.createProject(url: url("b"), name: "b", launchCommand: "claude")
        store.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(store.folders.map(\.displayName), ["b", "a"])
    }

    // MARK: - Persistence

    internal func testLabelsAndAssignmentsSurviveReload() throws {
        let store = makeStore()
        let work = try XCTUnwrap(store.createLabel(name: "Work", colorHex: "#22C55E", symbolName: "hammer.fill"))
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
    internal func testLoadsVersion1StateFile() {
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
    internal func testLoadDropsDanglingLabelIDs() throws {
        let store = makeStore()
        let work = try XCTUnwrap(store.createLabel(name: "Work"))
        store.createProject(url: url("api"), name: "API", launchCommand: "claude", labelIDs: [work.id])
        waitForSave()

        // Rewrite the file with the label removed but the assignment kept.
        let saved = try Data(contentsOf: stateFile)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        obj["labels"] = []
        try JSONSerialization.data(withJSONObject: obj).write(to: stateFile)

        let reloaded = makeStore()
        XCTAssertTrue(reloaded.folders[0].labelIDs.isEmpty)
        XCTAssertEqual(reloaded.sidebarGroups.map(\.title), ["Shortcuts"])
    }

    internal func testMissingStateFileStartsEmpty() {
        let store = FolderStore(fileURL: dir.appendingPathComponent("nope.json"))
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
    }

    internal func testCorruptStateFileStartsEmpty() {
        TestSupport.write("{ not json", to: stateFile)
        let store = makeStore()
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(store.labels.isEmpty)
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
