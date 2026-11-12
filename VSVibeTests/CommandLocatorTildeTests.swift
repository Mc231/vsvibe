@testable import VSVibe
import XCTest

internal final class CommandLocatorTildeTests: XCTestCase {
    internal func testTildePathThatDoesNotExistIsNotFound() {
        let command = "~/vsvibe-missing-\(UUID().uuidString)/tool"
        XCTAssertNil(CommandLocator.resolveExecutable(command, searchPaths: ["/usr/bin"]))
    }

    internal func testTildeInsideRelativePathIsNotExpanded() {
        // Only a leading `~/` is expanded; this relative path stays as-is and is missing.
        XCTAssertNil(CommandLocator.resolveExecutable("bin/~/tool", searchPaths: []))
    }

    internal func testAbsolutePathIsReturnedUnchanged() {
        XCTAssertEqual(CommandLocator.resolveExecutable("/bin/sh", searchPaths: []), "/bin/sh")
    }

    deinit {
        // No shared state to release.
    }
}
