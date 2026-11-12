@testable import VSVibe
import XCTest

internal final class TranscriptLocatorTests: XCTestCase {
    internal func testEncodedProjectNameReplacesSlashesAndDots() {
        let url = URL(fileURLWithPath: "/Users/x/pet/my.proj")
        XCTAssertEqual(TranscriptLocator.encodedProjectName(for: url), "-Users-x-pet-my-proj")
    }

    internal func testProjectDir() {
        let config = URL(fileURLWithPath: "/Users/x/.claude")
        let folder = URL(fileURLWithPath: "/Users/x/demo")
        let dir = TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
        XCTAssertEqual(dir.path, "/Users/x/.claude/projects/-Users-x-demo")
    }

    deinit {
        // Nothing to release.
    }
}
