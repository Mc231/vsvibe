@testable import VSVibe
import XCTest

internal final class SessionSnapshotFileTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var fileURL: URL { directory.appendingPathComponent("sessions.json") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("snapshot")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    internal func testWriteThenReadRoundTrips() {
        let snapshot = SessionSnapshot(
            panes: [
                PaneSnapshot(folderID: UUID(), claudeSessionID: "conv"),
                PaneSnapshot(folderID: UUID(), claudeSessionID: nil)
            ],
            focusedIndex: 1
        )
        SessionSnapshotFile.write(snapshot, to: fileURL)
        XCTAssertEqual(SessionSnapshotFile.read(from: fileURL), snapshot)
    }

    internal func testMissingOrCorruptFileReadsAsNil() throws {
        XCTAssertNil(SessionSnapshotFile.read(from: fileURL))
        try Data("{broken".utf8).write(to: fileURL)
        XCTAssertNil(SessionSnapshotFile.read(from: fileURL))
    }

    internal func testDecodesWithoutOptionalFields() throws {
        let folderID = UUID()
        let json = #"{"version":1,"panes":[{"folderID":"\#(folderID.uuidString)"}]}"#
        try Data(json.utf8).write(to: fileURL)
        let snapshot = try XCTUnwrap(SessionSnapshotFile.read(from: fileURL))
        XCTAssertEqual(snapshot.panes, [PaneSnapshot(folderID: folderID, claudeSessionID: nil)])
        XCTAssertNil(snapshot.focusedIndex)
    }

    internal func testWriteFailureIsSwallowedAndRemoveIsIdempotent() {
        let unwritable = directory.appendingPathComponent("missing/dir/sessions.json")
        SessionSnapshotFile.write(SessionSnapshot(panes: []), to: unwritable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unwritable.path))

        SessionSnapshotFile.write(SessionSnapshot(panes: []), to: fileURL)
        SessionSnapshotFile.remove(at: fileURL)
        SessionSnapshotFile.remove(at: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
