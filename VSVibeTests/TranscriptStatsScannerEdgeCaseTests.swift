@testable import VSVibe
import XCTest

internal final class TranscriptStatsScannerEdgeCaseTests: XCTestCase {
    private var configDir = URL(fileURLWithPath: "/")
    private let folderURL = URL(fileURLWithPath: "/Users/test/projects/edge-cases")
    private var transcriptDir = URL(fileURLWithPath: "/")

    override internal func setUp() {
        super.setUp()
        configDir = TestSupport.makeTempDir("claude-config-edge")
        transcriptDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
    }

    override internal func tearDown() {
        TestSupport.remove(configDir)
        super.tearDown()
    }

    internal func testTimestampWithoutFractionalSecondsIsParsed() throws {
        try write("a.jsonl", lines: [assistant(timestamp: "2026-03-04T12:00:00Z", output: 5)])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-04T12:00:00Z"))
        XCTAssertEqual(stat.days[DayKey.key(for: date)]?.outputTokens, 5)
    }

    internal func testMissingOrInvalidTimestampFallsBackToToday() throws {
        try write("a.jsonl", lines: [
            assistant(timestamp: nil, output: 1),
            assistant(timestamp: "yesterday-ish", output: 2)
        ])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))
        XCTAssertEqual(stat.days.count, 1)
        XCTAssertEqual(stat.days[DayKey.today()]?.outputTokens, 3)
        XCTAssertEqual(stat.days[DayKey.today()]?.assistantMessages, 2)
    }

    internal func testMalformedAndBlankLinesAreSkippedButConsumed() throws {
        try write("a.jsonl", lines: ["{not json\n", "\n", "[1, 2, 3]\n"])
        var stat = ProjectStat()
        XCTAssertFalse(scan(&stat))
        XCTAssertTrue(stat.days.isEmpty)
        let size = try fileSize("a.jsonl")
        XCTAssertEqual(stat.transcriptBytes["a.jsonl"], size)
    }

    internal func testFileWithoutCompleteLineIsLeftForLater() throws {
        try write("a.jsonl", lines: [String(assistant(timestamp: nil, output: 1).dropLast())])
        var stat = ProjectStat()
        XCTAssertFalse(scan(&stat))
        XCTAssertNil(stat.transcriptBytes["a.jsonl"])
        XCTAssertTrue(stat.days.isEmpty)
    }

    internal func testTruncatedFileIsRescannedFromStart() throws {
        try write("a.jsonl", lines: [assistant(timestamp: nil, output: 7)])
        var stat = ProjectStat()
        stat.transcriptBytes["a.jsonl"] = 10_000_000 // larger than the file: it was rotated
        XCTAssertTrue(scan(&stat))
        XCTAssertEqual(stat.days[DayKey.today()]?.outputTokens, 7)
        XCTAssertEqual(stat.transcriptBytes["a.jsonl"], try fileSize("a.jsonl"))
    }

    internal func testFullyConsumedFileAndNonTranscriptFilesAreIgnored() throws {
        try write("a.jsonl", lines: [assistant(timestamp: nil, output: 1)])
        try write("notes.txt", lines: [assistant(timestamp: nil, output: 100)])
        var stat = ProjectStat()
        XCTAssertTrue(scan(&stat))
        XCTAssertFalse(scan(&stat))
        XCTAssertEqual(stat.days[DayKey.today()]?.outputTokens, 1)
        XCTAssertNil(stat.transcriptBytes["notes.txt"])
    }

    private func assistant(timestamp: String?, output: Int) -> String {
        var object: [String: Any] = [
            "type": "assistant",
            "message": ["model": "claude-sonnet-4-6", "usage": ["output_tokens": output]]
        ]
        object["timestamp"] = timestamp
        return TestSupport.jsonl(object)
    }

    private func write(_ name: String, lines: [String]) throws {
        try Data(lines.joined().utf8).write(to: transcriptDir.appendingPathComponent(name))
    }

    private func fileSize(_ name: String) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: transcriptDir.appendingPathComponent(name).path
        )
        return try XCTUnwrap(attributes[.size] as? UInt64)
    }

    private func scan(_ stat: inout ProjectStat) -> Bool {
        TranscriptStatsScanner.scan(into: &stat, folderURL: folderURL, configDirs: [configDir])
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
