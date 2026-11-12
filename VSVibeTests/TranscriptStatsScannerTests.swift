@testable import VSVibe
import XCTest

internal final class TranscriptStatsScannerTests: XCTestCase {
    private let folderURL = URL(fileURLWithPath: "/Users/test/projects/demo")
    private var configDir = TestSupport.placeholderURL

    private var transcriptDir: URL {
        TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
    }

    override internal func setUp() {
        super.setUp()
        configDir = TestSupport.makeTempDir("claude-config")
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
    }

    override internal func tearDown() {
        TestSupport.remove(configDir)
        super.tearDown()
    }

    private func assistantLine(
        timestamp: String,
        model: String = "claude-opus-4-7",
        input: Int = 0,
        output: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        toolUses: Int = 0,
        sessionId: String = "s1"
    ) -> String {
        var content: [[String: Any]] = [["type": "text", "text": "hi"]]
        for _ in 0..<toolUses {
            content.append(["type": "tool_use", "name": "Bash"])
        }
        return TestSupport.jsonl([
            "type": "assistant",
            "timestamp": timestamp,
            "sessionId": sessionId,
            "message": [
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreation,
                    "cache_read_input_tokens": cacheRead
                ],
                "content": content
            ]
        ])
    }

    private func writeTranscript(_ name: String, _ lines: [String]) {
        let url = transcriptDir.appendingPathComponent(name)
        TestSupport.write(lines.joined(), to: url)
    }

    private func appendTranscript(_ name: String, _ line: String) throws {
        let url = transcriptDir.appendingPathComponent(name)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        try handle.close()
    }

    private func scan(_ stat: inout ProjectStat) -> Bool {
        TranscriptStatsScanner.scan(into: &stat, folderURL: folderURL, configDirs: [configDir])
    }

    internal func testBasicAggregation() throws {
        writeTranscript("a.jsonl", [
            assistantLine(
                timestamp: "2026-05-22T10:00:00.000Z",
                input: 100,
                output: 50,
                cacheCreation: 10,
                cacheRead: 5,
                toolUses: 2
            ),
            assistantLine(timestamp: "2026-05-22T11:00:00.000Z", output: 20, toolUses: 1)
        ])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))

        // Both lines fall on the same local day.
        XCTAssertEqual(stat.days.count, 1)
        let day = try XCTUnwrap(stat.days.values.first)
        XCTAssertEqual(day.assistantMessages, 2)
        XCTAssertEqual(day.inputTokens, 100)
        XCTAssertEqual(day.outputTokens, 70)
        XCTAssertEqual(day.cacheCreationTokens, 10)
        XCTAssertEqual(day.cacheReadTokens, 5)
        XCTAssertEqual(day.toolCalls, 3)
        XCTAssertEqual(day.modelMessageCounts["claude-opus-4-7"], 2)
        XCTAssertEqual(day.transcriptSessionIds, ["s1"])
        XCTAssertGreaterThan(day.costUSD, 0)
    }

    internal func testCostMatchesModelPricing() throws {
        writeTranscript("a.jsonl", [
            assistantLine(timestamp: "2026-05-22T10:00:00.000Z", model: "claude-opus-4-7", input: 1_000_000)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        // 1M opus input tokens at $15/M.
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).costUSD, 15.0, accuracy: 0.0001)
    }

    internal func testSeparateDayBuckets() {
        writeTranscript("a.jsonl", [
            assistantLine(timestamp: "2026-05-20T10:00:00.000Z", output: 1),
            assistantLine(timestamp: "2026-05-21T10:00:00.000Z", output: 1)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(stat.days.count, 2)
    }

    internal func testIncrementalScanDoesNotDoubleCount() throws {
        writeTranscript("a.jsonl", [assistantLine(timestamp: "2026-05-22T10:00:00.000Z", output: 10)])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))
        // Second scan with no new bytes: nothing changes.
        XCTAssertFalse(scan(&stat))
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).assistantMessages, 1)

        try appendTranscript("a.jsonl", assistantLine(timestamp: "2026-05-22T12:00:00.000Z", output: 5))
        XCTAssertTrue(scan(&stat))
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).assistantMessages, 2)
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).outputTokens, 15)
    }

    internal func testPartialLastLineDeferred() throws {
        // Write a complete line plus a partial (no trailing newline) line.
        let complete = assistantLine(timestamp: "2026-05-22T10:00:00.000Z", output: 1)
        let partial = String(assistantLine(timestamp: "2026-05-22T11:00:00.000Z", output: 9).dropLast(5))
        TestSupport.write(complete + partial, to: transcriptDir.appendingPathComponent("a.jsonl"))

        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).assistantMessages, 1)

        // Complete the partial line; the deferred line is now counted.
        try appendTranscript("a.jsonl", "9}}}\n")
        _ = scan(&stat)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(stat.days.values.first).assistantMessages, 1)
    }

    internal func testNonAssistantLinesIgnored() throws {
        writeTranscript("a.jsonl", [
            TestSupport.jsonl(["type": "user", "timestamp": "2026-05-22T10:00:00.000Z", "message": ["content": "hi"]]),
            assistantLine(timestamp: "2026-05-22T10:01:00.000Z", output: 3)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(try XCTUnwrap(stat.days.values.first).assistantMessages, 1)
    }

    internal func testDistinctSessionsAcrossFiles() throws {
        writeTranscript("a.jsonl", [assistantLine(timestamp: "2026-05-22T10:00:00.000Z", output: 1, sessionId: "s1")])
        writeTranscript("b.jsonl", [assistantLine(timestamp: "2026-05-22T11:00:00.000Z", output: 1, sessionId: "s2")])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(Set(try XCTUnwrap(stat.days.values.first).transcriptSessionIds), ["s1", "s2"])
    }

    internal func testHighContextDetection() throws {
        // 180k context tokens > 85% of the 200k window.
        writeTranscript("a.jsonl", [assistantLine(timestamp: "2026-05-22T10:00:00.000Z", input: 180_000)])
        var stat = ProjectStat()
        _ = scan(&stat)
        let day = try XCTUnwrap(stat.days.values.first)
        XCTAssertEqual(day.highContextMessages, 1)
        XCTAssertEqual(day.peakContextTokens, 180_000)
    }

    internal func testMissingDirReturnsFalse() {
        var stat = ProjectStat()
        let other = URL(fileURLWithPath: "/Users/test/projects/nonexistent")
        XCTAssertFalse(TranscriptStatsScanner.scan(into: &stat, folderURL: other, configDirs: [configDir]))
        XCTAssertTrue(stat.days.isEmpty)
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
