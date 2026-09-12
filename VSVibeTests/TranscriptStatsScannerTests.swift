import XCTest
@testable import VSVibe

final class TranscriptStatsScannerTests: XCTestCase {
    private var configDir: URL!
    private var folderURL: URL!
    private var transcriptDir: URL!

    override func setUp() {
        super.setUp()
        configDir = TestSupport.makeTempDir("claude-config")
        folderURL = URL(fileURLWithPath: "/Users/test/projects/demo")
        transcriptDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        TestSupport.remove(configDir)
        super.tearDown()
    }

    private func assistantLine(ts: String,
                               model: String = "claude-opus-4-7",
                               input: Int = 0,
                               output: Int = 0,
                               cacheCreation: Int = 0,
                               cacheRead: Int = 0,
                               toolUses: Int = 0,
                               sessionId: String = "s1") -> String {
        var content: [[String: Any]] = [["type": "text", "text": "hi"]]
        for _ in 0..<toolUses { content.append(["type": "tool_use", "name": "Bash"]) }
        return TestSupport.jsonl([
            "type": "assistant",
            "timestamp": ts,
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

    private func appendTranscript(_ name: String, _ line: String) {
        let url = transcriptDir.appendingPathComponent(name)
        let handle = try! FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    }

    private func scan(_ stat: inout ProjectStat) -> Bool {
        TranscriptStatsScanner.scan(into: &stat, folderURL: folderURL, configDirs: [configDir])
    }

    func testBasicAggregation() {
        writeTranscript("a.jsonl", [
            assistantLine(ts: "2026-05-22T10:00:00.000Z", input: 100, output: 50, cacheCreation: 10, cacheRead: 5, toolUses: 2),
            assistantLine(ts: "2026-05-22T11:00:00.000Z", output: 20, toolUses: 1)
        ])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))

        // Both lines fall on the same local day.
        XCTAssertEqual(stat.days.count, 1)
        let day = stat.days.values.first!
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

    func testCostMatchesModelPricing() {
        writeTranscript("a.jsonl", [
            assistantLine(ts: "2026-05-22T10:00:00.000Z", model: "claude-opus-4-7", input: 1_000_000)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        // 1M opus input tokens at $15/M.
        XCTAssertEqual(stat.days.values.first!.costUSD, 15.0, accuracy: 0.0001)
    }

    func testSeparateDayBuckets() {
        writeTranscript("a.jsonl", [
            assistantLine(ts: "2026-05-20T10:00:00.000Z", output: 1),
            assistantLine(ts: "2026-05-21T10:00:00.000Z", output: 1)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(stat.days.count, 2)
    }

    func testIncrementalScanDoesNotDoubleCount() {
        writeTranscript("a.jsonl", [assistantLine(ts: "2026-05-22T10:00:00.000Z", output: 10)])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))
        // Second scan with no new bytes: nothing changes.
        XCTAssertFalse(scan(&stat))
        XCTAssertEqual(stat.days.values.first!.assistantMessages, 1)

        appendTranscript("a.jsonl", assistantLine(ts: "2026-05-22T12:00:00.000Z", output: 5))
        XCTAssertTrue(scan(&stat))
        XCTAssertEqual(stat.days.values.first!.assistantMessages, 2)
        XCTAssertEqual(stat.days.values.first!.outputTokens, 15)
    }

    func testPartialLastLineDeferred() {
        // Write a complete line plus a partial (no trailing newline) line.
        let complete = assistantLine(ts: "2026-05-22T10:00:00.000Z", output: 1)
        let partial = String(assistantLine(ts: "2026-05-22T11:00:00.000Z", output: 9).dropLast(5))
        TestSupport.write(complete + partial, to: transcriptDir.appendingPathComponent("a.jsonl"))

        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(stat.days.values.first!.assistantMessages, 1)

        // Complete the partial line; the deferred line is now counted.
        appendTranscript("a.jsonl", "9}}}\n")
        _ = scan(&stat)
        XCTAssertGreaterThanOrEqual(stat.days.values.first!.assistantMessages, 1)
    }

    func testNonAssistantLinesIgnored() {
        writeTranscript("a.jsonl", [
            TestSupport.jsonl(["type": "user", "timestamp": "2026-05-22T10:00:00.000Z", "message": ["content": "hi"]]),
            assistantLine(ts: "2026-05-22T10:01:00.000Z", output: 3)
        ])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(stat.days.values.first!.assistantMessages, 1)
    }

    func testDistinctSessionsAcrossFiles() {
        writeTranscript("a.jsonl", [assistantLine(ts: "2026-05-22T10:00:00.000Z", output: 1, sessionId: "s1")])
        writeTranscript("b.jsonl", [assistantLine(ts: "2026-05-22T11:00:00.000Z", output: 1, sessionId: "s2")])
        var stat = ProjectStat()
        _ = scan(&stat)
        XCTAssertEqual(Set(stat.days.values.first!.transcriptSessionIds), ["s1", "s2"])
    }

    func testHighContextDetection() {
        // 180k context tokens > 85% of the 200k window.
        writeTranscript("a.jsonl", [assistantLine(ts: "2026-05-22T10:00:00.000Z", input: 180_000)])
        var stat = ProjectStat()
        _ = scan(&stat)
        let day = stat.days.values.first!
        XCTAssertEqual(day.highContextMessages, 1)
        XCTAssertEqual(day.peakContextTokens, 180_000)
    }

    func testMissingDirReturnsFalse() {
        var stat = ProjectStat()
        let other = URL(fileURLWithPath: "/Users/test/projects/nonexistent")
        XCTAssertFalse(TranscriptStatsScanner.scan(into: &stat, folderURL: other, configDirs: [configDir]))
        XCTAssertTrue(stat.days.isEmpty)
    }
}
