@testable import VSVibe
import XCTest

internal final class EnvBuilderTests: XCTestCase {
    private func dict(_ pairs: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for pair in pairs {
            guard let separator = pair.firstIndex(of: "=") else {
                continue
            }
            result[String(pair[..<separator])] = String(pair[pair.index(after: separator)...])
        }
        return result
    }

    internal func testSetsTerminalEnv() {
        let env = dict(EnvBuilder.build())
        XCTAssertEqual(env["TERM"], "xterm-256color")
        XCTAssertEqual(env["COLORTERM"], "truecolor")
        XCTAssertEqual(env["VSVIBE"], "1")
    }

    internal func testPathContainsPrependedDirs() {
        let env = dict(EnvBuilder.build())
        let path = env["PATH"] ?? ""
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
        XCTAssertTrue(path.contains("/usr/local/bin"))
    }

    internal func testPathHasNoDuplicates() {
        let env = dict(EnvBuilder.build())
        let parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(parts.count, Set(parts).count)
    }

    internal func testExportsPaneIDOnlyWhenGiven() {
        let paneID = UUID()
        XCTAssertEqual(dict(EnvBuilder.build(paneID: paneID))[EnvBuilder.paneIDKey], paneID.uuidString)
        XCTAssertEqual(EnvBuilder.paneIDKey, "VSVIBE_PANE_ID")
        XCTAssertNil(dict(EnvBuilder.build())[EnvBuilder.paneIDKey])
    }

    internal func testExtraPathsIncluded() {
        let env = dict(EnvBuilder.build(extraPaths: ["/custom/tool/bin"]))
        XCTAssertTrue((env["PATH"] ?? "").contains("/custom/tool/bin"))
    }

    deinit {
        // Nothing to release.
    }
}
