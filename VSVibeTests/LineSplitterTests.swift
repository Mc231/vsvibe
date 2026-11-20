@testable import VSVibe
import XCTest

/// Splitting a byte stream into lines, and decoding event lines.
internal final class LineSplitterTests: XCTestCase {
    private func texts(_ lines: [Data]) -> [String] {
        lines.map { String(bytes: $0, encoding: .utf8) ?? "<binary>" }
    }

    internal func testCompleteLinesAreReturnedInOrder() {
        var splitter = LineSplitter()
        XCTAssertEqual(texts(splitter.append(Data("a\nbb\n\nccc\n".utf8))), ["a", "bb", "", "ccc"])
    }

    internal func testPartialLineIsKeptUntilItsNewline() {
        var splitter = LineSplitter()
        XCTAssertEqual(texts(splitter.append(Data("first\nsec".utf8))), ["first"])
        XCTAssertEqual(texts(splitter.append(Data("o".utf8))), [])
        XCTAssertEqual(texts(splitter.append(Data("nd\nthi".utf8))), ["second"])
        XCTAssertEqual(texts(splitter.append(Data("rd\n".utf8))), ["third"])
    }

    internal func testResetDropsThePartialLine() {
        var splitter = LineSplitter()
        _ = splitter.append(Data("stale".utf8))
        splitter.reset()
        XCTAssertEqual(texts(splitter.append(Data("fresh\n".utf8))), ["fresh"])
    }

    internal func testByteByByteFeedingMatchesOneChunk() {
        let text = "{\"a\":1}\n{\"b\":2}\nrest"
        var whole = LineSplitter()
        var bytes = LineSplitter()
        let expected = texts(whole.append(Data(text.utf8)))
        var collected: [Data] = []
        for byte in Data(text.utf8) {
            collected += bytes.append(Data([byte]))
        }
        XCTAssertEqual(texts(collected), expected)
        XCTAssertEqual(expected, ["{\"a\":1}", "{\"b\":2}"])
    }

    internal func testEventLinesDecode() throws {
        let line = Data(#"{"event":"Stop","projectDir":"/srv/app","ts":5,"paneId":"\#(UUID().uuidString)"}"#.utf8)
        let event = try XCTUnwrap(HookEvent.decoded(fromLine: line))
        XCTAssertEqual(event.event, .stop)
        XCTAssertEqual(event.projectDir, "/srv/app")
        XCTAssertNotNil(event.paneID)
        XCTAssertNil(HookEvent.decoded(fromLine: Data()))
        XCTAssertNil(HookEvent.decoded(fromLine: Data("not json".utf8)))
        XCTAssertNil(HookEvent.decoded(fromLine: Data([0xFF, 0xFE])))
    }

    deinit {
        // Stateless tests.
    }
}
