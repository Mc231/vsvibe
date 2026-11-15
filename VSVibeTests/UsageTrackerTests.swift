@testable import VSVibe
import XCTest

internal final class UsageTrackerTests: XCTestCase {
    private var config = TestSupport.placeholderURL
    private var line = ""

    private var folder: URL {
        config.appendingPathComponent("project")
    }

    private var latest: TranscriptSource {
        .latest(folderURL: folder, configDir: config)
    }

    private var transcript: URL {
        TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
            .appendingPathComponent("session.jsonl")
    }

    override internal func setUpWithError() throws {
        try super.setUpWithError()
        config = TestSupport.makeTempDir()
        let directory = TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        line = TestSupport.jsonl([
            "type": "assistant",
            "message": [
                "model": "claude-sonnet-4-6",
                "usage": [
                    "input_tokens": 10,
                    "output_tokens": 5,
                    "cache_creation_input_tokens": 2,
                    "cache_read_input_tokens": 3
                ]
            ]
        ])
    }

    override internal func tearDown() {
        TestSupport.remove(config)
        super.tearDown()
    }

    internal func testIncrementalReadIncompleteLinesAndMalformedRecords() throws {
        var reader = TranscriptUsageReader(source: latest)
        XCTAssertNil(reader.poll())
        let malformed = "\nnot json\n{}\n{\"type\":\"user\"}\n{\"type\":\"assistant\"}\n"
        let modelOnly = "{\"type\":\"assistant\",\"message\":{\"model\":\"test\"}}\n"
        TestSupport.write(malformed + modelOnly + line, to: transcript)
        let usage = try XCTUnwrap(reader.poll())
        XCTAssertEqual(usage.totalInput, 10)
        XCTAssertEqual(usage.totalOutput, 5)
        XCTAssertEqual(usage.totalCacheCreation, 2)
        XCTAssertEqual(usage.totalCacheRead, 3)
        XCTAssertEqual(usage.lastContextTokens, 15)
        XCTAssertEqual(usage.lastModel, "claude-sonnet-4-6")
        XCTAssertNotNil(usage.updatedAt)
        XCTAssertNil(reader.poll())
        let handle = try FileHandle(forWritingTo: transcript)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.dropLast().utf8))
        XCTAssertNil(reader.poll())
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        XCTAssertEqual(reader.poll()?.messageCount, 2)
    }

    internal func testLargeTranscriptProcessesBoundedChunksWithoutDoubleCounting() throws {
        TestSupport.write(String(repeating: line, count: 4_000), to: transcript)
        var reader = TranscriptUsageReader(source: latest, chunkSize: 4_096)
        var latest = reader.poll()
        XCTAssertTrue(reader.hasMoreData)
        XCTAssertLessThan(try XCTUnwrap(latest).messageCount, 100)
        while reader.hasMoreData {
            if let update = reader.poll() {
                latest = update
            }
        }
        XCTAssertEqual(latest?.messageCount, 4_000)
        XCTAssertEqual(latest?.totalInput, 40_000)
        XCTAssertNil(reader.poll())
    }

    internal func testTruncationAndTranscriptRotationResetTotals() throws {
        TestSupport.write(line + line, to: transcript)
        var reader = TranscriptUsageReader(source: latest)
        XCTAssertEqual(reader.poll()?.messageCount, 2)
        TestSupport.write(line, to: transcript)
        XCTAssertEqual(reader.poll()?.messageCount, 1)
        let next = transcript.deletingLastPathComponent().appendingPathComponent("next.jsonl")
        TestSupport.write(line + line + line, to: next)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: next.path
        )
        XCTAssertEqual(reader.poll()?.messageCount, 3)
    }

    internal func testMissingUsageFieldsDefaultToZeroAndChunksCanSplitEveryByte() {
        TestSupport.write("{\"type\":\"assistant\",\"message\":{\"usage\":{}}}\n", to: transcript)
        var reader = TranscriptUsageReader(source: latest, chunkSize: 1)
        var latest = reader.poll()
        while reader.hasMoreData {
            if let update = reader.poll() {
                latest = update
            }
        }
        XCTAssertEqual(latest?.messageCount, 1)
        XCTAssertEqual(latest?.totalInput, 0)
        XCTAssertNil(latest?.lastModel)
    }

    @MainActor
    internal func testPollingPublishesOnMainActorAndStopCancels() async {
        TestSupport.write(line, to: transcript)
        let updated = expectation(description: "usage delivered")
        var deliveries = 0
        let tracker = UsageTracker(source: latest) { usage in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(usage.messageCount, 1)
            deliveries += 1
            updated.fulfill()
        }
        tracker.start()
        tracker.start() // Replacing a task must not publish a stale result.
        await fulfillment(of: [updated], timeout: 5)
        tracker.stop()
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(deliveries, 1)
    }

    // MARK: - Transcript source

    internal func testSourceSelectionPrefersThePanesOwnTranscript() {
        let fallback = config.appendingPathComponent("alias")
        let own = "/c/projects/p/id.jsonl"
        XCTAssertEqual(
            TranscriptSource.select(transcriptPath: own, fallbackConfigDir: fallback, folderURL: folder),
            .file(URL(fileURLWithPath: own))
        )
        XCTAssertEqual(
            TranscriptSource.select(transcriptPath: own, fallbackConfigDir: nil, folderURL: folder),
            .file(URL(fileURLWithPath: own))
        )
        for invalid in [nil, "", "relative/id.jsonl", "/c/projects/p/id.txt"] {
            XCTAssertEqual(
                TranscriptSource.select(transcriptPath: invalid, fallbackConfigDir: fallback, folderURL: folder),
                .latest(folderURL: folder, configDir: fallback),
                invalid ?? "nil"
            )
            XCTAssertNil(TranscriptSource.select(transcriptPath: invalid, fallbackConfigDir: nil, folderURL: folder))
        }
    }

    internal func testFileSourceReadsOnlyThatTranscript() throws {
        let own = transcript.deletingLastPathComponent().appendingPathComponent("own.jsonl")
        XCTAssertNil(TranscriptSource.file(own).currentTranscript())
        TestSupport.write(line, to: own)
        // A newer transcript of another pane in the same folder must not be picked up.
        TestSupport.write(line + line + line, to: transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: transcript.path
        )
        XCTAssertEqual(latest.currentTranscript()?.lastPathComponent, "session.jsonl")
        var reader = TranscriptUsageReader(source: .file(own))
        XCTAssertEqual(reader.poll()?.messageCount, 1)
        XCTAssertNil(reader.poll())
        XCTAssertEqual(reader.source, .file(own))
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
