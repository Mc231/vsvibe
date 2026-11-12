@testable import VSVibe
import XCTest

@MainActor
internal final class EventWatcherTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var received: [HookEvent] = []

    private var eventsURL: URL { directory.appendingPathComponent("nested/events.jsonl") }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("events")
        received = []
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func makeWatcher(pollInterval: TimeInterval = 60) -> EventWatcher {
        EventWatcher(url: eventsURL, pollInterval: pollInterval) { [weak self] event in
            self?.received.append(event)
        }
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: eventsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func line(_ event: String, dir: String = "/p") -> String {
        #"{"event":"\#(event)","projectDir":"\#(dir)","ts":1}"# + "\n"
    }

    internal func testStartCreatesFileAndSkipsExistingLines() throws {
        let watcher = makeWatcher()
        watcher.start()
        XCTAssertTrue(watcher.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventsURL.path))

        try append(line("Stop"))
        watcher.stop()
        XCTAssertFalse(watcher.isRunning)

        let restarted = makeWatcher()
        restarted.start()
        restarted.drain()
        XCTAssertTrue(received.isEmpty, "lines written before start() are not replayed")
        restarted.stop()
    }

    internal func testDrainDispatchesNewLinesInOrder() throws {
        let watcher = makeWatcher()
        watcher.start()
        try append(line("Stop") + line("Notification", dir: "/q"))
        watcher.drain()
        XCTAssertEqual(received.map(\.event), [.stop, .notification])
        XCTAssertEqual(received.map(\.projectDir), ["/p", "/q"])

        watcher.drain()
        XCTAssertEqual(received.count, 2, "nothing new, nothing dispatched")
        watcher.stop()
    }

    internal func testPartialLineIsHeldUntilNewlineArrives() throws {
        let watcher = makeWatcher()
        watcher.start()
        let full = line("SubagentStop")
        try append(String(full.prefix(10)))
        watcher.drain()
        XCTAssertTrue(received.isEmpty)

        try append(String(full.dropFirst(10)))
        watcher.drain()
        XCTAssertEqual(received.map(\.event), [.subagentStop])
        watcher.stop()
    }

    internal func testBlankAndMalformedLinesAreSkipped() throws {
        let watcher = makeWatcher()
        watcher.start()
        try append("\n" + "not json\n" + line("Stop"))
        watcher.drain()
        XCTAssertEqual(received.map(\.event), [.stop])
        watcher.stop()
    }

    internal func testTruncatedFileIsReadFromTheStart() throws {
        let watcher = makeWatcher()
        watcher.start()
        try append(line("Stop") + line("Stop"))
        watcher.drain()
        XCTAssertEqual(received.count, 2)

        try Data(line("Notification").utf8).write(to: eventsURL)
        watcher.drain()
        XCTAssertEqual(received.map(\.event), [.stop, .stop, .notification])
        watcher.stop()
    }

    internal func testDrainWithoutFileIsANoOp() throws {
        let watcher = makeWatcher()
        watcher.start()
        try append(line("Stop"))
        try FileManager.default.removeItem(at: eventsURL)
        watcher.drain()
        XCTAssertTrue(received.isEmpty)
        watcher.stop()
    }

    internal func testUnreadableFileIsRetriedLater() throws {
        let watcher = makeWatcher()
        watcher.start()
        try append(line("Stop"))
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: eventsURL.path)
        watcher.drain()
        XCTAssertTrue(received.isEmpty)

        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: eventsURL.path)
        watcher.drain()
        XCTAssertEqual(received.map(\.event), [.stop])
        watcher.stop()
    }

    internal func testTimerPollsTheFile() async throws {
        let watcher = makeWatcher(pollInterval: 0.05)
        watcher.start()
        try append(line("Notification"))
        let delivered = await AsyncWait.until { !self.received.isEmpty }
        XCTAssertTrue(delivered)
        XCTAssertEqual(received.first?.event, .notification)
        watcher.stop()
    }

    internal func testRestartReplacesTheTimer() {
        let watcher = makeWatcher()
        watcher.start()
        watcher.start()
        XCTAssertTrue(watcher.isRunning)
        watcher.stop()
        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
