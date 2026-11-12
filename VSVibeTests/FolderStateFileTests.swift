@testable import VSVibe
import XCTest

internal final class FolderStateFileTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    private var fileURL: URL { directory.appendingPathComponent("state.json") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("statefile")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testMissingFileReadsAsNil() {
        XCTAssertNil(FolderStateFile.read(from: fileURL))
    }

    internal func testCorruptFileReadsAsNil() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertNil(FolderStateFile.read(from: fileURL))
    }

    internal func testWriteThenReadRoundTripsAndDropsUnknownLabels() throws {
        let label = ProjectLabel(name: "Work")
        let folder = FolderEntry(url: URL(fileURLWithPath: "/x/a"), labelIDs: [label.id, UUID()])
        let state = PersistedState(version: PersistedState.currentVersion, folders: [folder], labels: [label])
        FolderStateFile.write(state, to: fileURL)

        let loaded = try XCTUnwrap(FolderStateFile.read(from: fileURL))
        XCTAssertEqual(loaded.labels.map(\.id), [label.id])
        XCTAssertEqual(loaded.folders.map(\.id), [folder.id])
        XCTAssertEqual(loaded.folders.first?.labelIDs, [label.id])
    }

    internal func testWriteToMissingDirectoryIsLoggedNotThrown() {
        let target = directory.appendingPathComponent("missing/dir/state.json")
        FolderStateFile.write(PersistedState.empty, to: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
