@testable import VSVibe
import XCTest

internal final class AppPathsTests: XCTestCase {
    private var base = FileManager.default.temporaryDirectory

    override internal func setUp() {
        super.setUp()
        base = TestSupport.makeTempDir("apppaths")
    }

    override internal func tearDown() {
        TestSupport.remove(base)
        super.tearDown()
    }

    internal func testBaseDirectoryPrefersSystemReportedURL() {
        let found = URL(fileURLWithPath: "/tmp/support", isDirectory: true)
        XCTAssertEqual(AppPaths.baseDirectory(found: found, home: "/Users/nobody"), found)
    }

    internal func testBaseDirectoryFallsBackToHomeLibrary() {
        let base = AppPaths.baseDirectory(found: nil, home: "/Users/nobody")
        XCTAssertEqual(base.path, "/Users/nobody/Library/Application Support")
    }

    internal func testAppDirectoryIsCreatedOnFirstAccess() {
        let dir = AppPaths.appDirectory(in: base)
        XCTAssertEqual(dir.lastPathComponent, AppPaths.appName)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    internal func testAppDirectoryKeepsExistingContents() throws {
        let dir = AppPaths.appDirectory(in: base)
        let marker = dir.appendingPathComponent("marker.txt")
        try Data("keep".utf8).write(to: marker)
        XCTAssertEqual(AppPaths.appDirectory(in: base), dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    internal func testSessionsFileLivesInAppDirectory() {
        XCTAssertEqual(AppPaths.sessionsFile.lastPathComponent, "sessions.json")
        XCTAssertEqual(AppPaths.sessionsFile.deletingLastPathComponent(), AppPaths.applicationSupportDirectory)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
