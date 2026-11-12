@testable import VSVibe
import XCTest

internal final class EnvBuilderSearchPathsTests: XCTestCase {
    internal func testSearchPathsContainWellKnownDirs() {
        let paths = EnvBuilder.searchPaths()
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
    }

    internal func testSearchPathsHaveNoDuplicates() {
        let paths = EnvBuilder.searchPaths()
        XCTAssertEqual(paths.count, Set(paths).count)
    }

    internal func testSearchPathsMatchBuiltPATH() {
        let paths = EnvBuilder.searchPaths()
        let built = EnvBuilder.build()
            .first { $0.hasPrefix("PATH=") }?
            .dropFirst("PATH=".count)
        XCTAssertEqual(String(built ?? ""), paths.joined(separator: ":"))
    }

    internal func testExtraPathsIncludedInSearchPaths() {
        XCTAssertTrue(EnvBuilder.searchPaths(extraPaths: ["/custom/tool/bin"]).contains("/custom/tool/bin"))
    }

    deinit {
        // Nothing to release.
    }
}
