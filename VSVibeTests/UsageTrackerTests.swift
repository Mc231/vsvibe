import XCTest
@testable import VSVibe

final class UsageTrackerTests: XCTestCase {
    private var config: URL!
    private var folder: URL!
    private var transcript: URL!

    override func setUpWithError() throws {
        config = TestSupport.makeTempDir()
        folder = config.appendingPathComponent("project")
        let directory = TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        transcript = directory.appendingPathComponent("session.jsonl")
    }
    override func tearDown() {
        TestSupport.remove(config)
        super.tearDown()
    }
    private var line: String {
        TestSupport.jsonl(["type": "assistant", "message": ["model": "claude-sonnet-4-6", "usage": [
            "input_tokens": 10, "output_tokens": 5, "cache_creation_input_tokens": 2, "cache_read_input_tokens": 3
        ]]])
    }

    func testIncrementalReadIncompleteLinesAndMalformedRecords() throws {
        var reader = TranscriptUsageReader(folderURL: folder, configDir: config)
        XCTAssertNil(reader.poll())
        TestSupport.write("\nnot json\n{}\n{\"type\":\"user\"}\n{\"type\":\"assistant\"}\n" +
                          "{\"type\":\"assistant\",\"message\":{\"model\":\"test\"}}\n" + line, to: transcript)
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

    func testLargeTranscriptProcessesBoundedChunksWithoutDoubleCounting() throws {
        TestSupport.write(String(repeating: line, count: 4000), to: transcript)
        var reader = TranscriptUsageReader(folderURL: folder, configDir: config, chunkSize: 4096)
        var latest = reader.poll()
        XCTAssertTrue(reader.hasMoreData)
        XCTAssertLessThan(try XCTUnwrap(latest).messageCount, 100)
        while reader.hasMoreData {
            if let update = reader.poll() { latest = update }
        }
        XCTAssertEqual(latest?.messageCount, 4000)
        XCTAssertEqual(latest?.totalInput, 40000)
        XCTAssertNil(reader.poll())
    }

    func testTruncationAndTranscriptRotationResetTotals() throws {
        TestSupport.write(line + line, to: transcript)
        var reader = TranscriptUsageReader(folderURL: folder, configDir: config)
        XCTAssertEqual(reader.poll()?.messageCount, 2)
        TestSupport.write(line, to: transcript)
        XCTAssertEqual(reader.poll()?.messageCount, 1)
        let next = transcript.deletingLastPathComponent().appendingPathComponent("next.jsonl")
        TestSupport.write(line + line + line, to: next)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: next.path)
        XCTAssertEqual(reader.poll()?.messageCount, 3)
    }

    func testMissingUsageFieldsDefaultToZeroAndChunksCanSplitEveryByte() {
        TestSupport.write("{\"type\":\"assistant\",\"message\":{\"usage\":{}}}\n", to: transcript)
        var reader = TranscriptUsageReader(folderURL: folder, configDir: config, chunkSize: 1)
        var latest = reader.poll()
        while reader.hasMoreData {
            if let update = reader.poll() { latest = update }
        }
        XCTAssertEqual(latest?.messageCount, 1)
        XCTAssertEqual(latest?.totalInput, 0)
        XCTAssertNil(latest?.lastModel)
    }

    @MainActor
    func testPollingPublishesOnMainActorAndStopCancels() async {
        TestSupport.write(line, to: transcript)
        let updated = expectation(description: "usage delivered")
        var deliveries = 0
        let tracker = UsageTracker(folderURL: folder, configDir: config) { usage in
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
}
