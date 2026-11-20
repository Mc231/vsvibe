@testable import VSVibe
import XCTest

/// Token usage from transcript bytes fed in arbitrary chunks.
internal final class UsageAccumulatorTests: XCTestCase {
    private static let transcript = """
        {"type":"user","message":{"content":"hi"}}
        {"type":"assistant","message":{"model":"claude-opus-4","usage":{"input_tokens":10,"output_tokens":5,\
        "cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}
        not json
        {"type":"assistant","message":{"model":"claude-sonnet-4"}}
        {"type":"assistant","message":{"usage":{"input_tokens":1,"output_tokens":2}}}

        """

    private let now = Date(timeIntervalSince1970: 1_000)

    internal func testWholeTranscriptSumsAssistantUsage() throws {
        var accumulator = UsageAccumulator()
        let usage = try XCTUnwrap(accumulator.consume(Data(Self.transcript.utf8), now: now))

        XCTAssertEqual(usage.totalInput, 11)
        XCTAssertEqual(usage.totalOutput, 7)
        XCTAssertEqual(usage.totalCacheCreation, 100)
        XCTAssertEqual(usage.totalCacheRead, 1_000)
        XCTAssertEqual(usage.messageCount, 2)
        XCTAssertEqual(usage.lastContextTokens, 1)
        XCTAssertEqual(usage.lastModel, "claude-sonnet-4")
        XCTAssertEqual(usage.updatedAt, now)
        XCTAssertEqual(accumulator.usage, usage)
    }

    internal func testSmallChunksGiveTheSameTotals() throws {
        var whole = UsageAccumulator()
        let expected = try XCTUnwrap(whole.consume(Data(Self.transcript.utf8), now: now))

        var chunked = UsageAccumulator()
        var last: SessionUsage?
        let bytes = Data(Self.transcript.utf8)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let end = min(index + 7, bytes.endIndex)
            last = chunked.consume(bytes.subdata(in: index..<end), now: now) ?? last
            index = end
        }
        XCTAssertEqual(last, expected)
    }

    internal func testChunksWithoutCompleteAssistantLinesReportNothing() {
        var accumulator = UsageAccumulator()
        XCTAssertNil(accumulator.consume(Data(#"{"type":"assistant","message":{"usage":{"input_tok"#.utf8)))
        XCTAssertNil(accumulator.consume(Data("{\"type\":\"user\"}\n".utf8)))
        XCTAssertEqual(accumulator.usage, SessionUsage())
    }

    deinit {
        // Stateless tests.
    }
}
