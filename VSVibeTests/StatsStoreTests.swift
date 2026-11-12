@testable import VSVibe
import XCTest

@MainActor
internal final class StatsStoreTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Users/test/projects/demo")
    private var directory = TestSupport.placeholderURL

    private var fileURL: URL {
        directory.appendingPathComponent("stats.json")
    }

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("stats")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    private func day(cost: Double, messages: Int, sessions: [String]) -> DayStat {
        var stat = DayStat()
        stat.costUSD = cost
        stat.assistantMessages = messages
        stat.transcriptSessionIds = sessions
        return stat
    }

    internal func testRecordPaneOpened() {
        let store = StatsStore(fileURL: fileURL)
        store.recordPaneOpened(folderURL: folder)
        store.recordPaneOpened(folderURL: folder)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .today).panesOpened, 2)
    }

    internal func testScanUsesNewlyRegisteredAliasesAndDeduplicatesConfigDirectories() async throws {
        let aliases = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        let store = StatsStore(fileURL: fileURL) { aliases.customAliases }
        let config = directory.appendingPathComponent("config")
        let transcripts = TranscriptLocator.projectDir(claudeConfigDir: config, folderURL: folder)
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        let line = TestSupport.jsonl([
            "type": "assistant",
            "timestamp": "2026-05-22T10:00:00.000Z",
            "sessionId": "custom-session",
            "message": [
                "model": "claude-opus-4-7",
                "usage": ["input_tokens": 100, "output_tokens": 20],
                "content": [["type": "text", "text": "hi"]]
            ]
        ])
        try line.write(to: transcripts.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        await store.scanTranscripts(forFolderURL: folder)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).assistantMessages, 0)
        try aliases.save(command: "work", configPath: config.path)
        try aliases.save(command: "work-two", configPath: config.path)
        await store.scanTranscripts(forFolderURL: folder)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).assistantMessages, 1)
        await store.scanTranscripts(forFolderURL: folder)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).inputTokens, 100)
    }

    internal func testRecordActiveTimeIgnoresNonPositive() {
        let store = StatsStore(fileURL: fileURL)
        store.recordActiveTime(folderURL: folder, seconds: 30)
        store.recordActiveTime(folderURL: folder, seconds: 0)
        store.recordActiveTime(folderURL: folder, seconds: -5)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .today).activeSeconds, 30, accuracy: 0.001)
    }

    internal func testRecordHookEvents() {
        let store = StatsStore(fileURL: fileURL)
        store.recordHookEvent(folderURL: folder, kind: .notification)
        store.recordHookEvent(folderURL: folder, kind: .stop)
        store.recordHookEvent(folderURL: folder, kind: .stop)
        store.recordHookEvent(folderURL: folder, kind: .subagentStop)
        store.recordHookEvent(folderURL: folder, kind: .unknown) // no-op

        let summary = store.summary(forFolderURL: folder, window: .today)
        XCTAssertEqual(summary.notifications, 1)
        XCTAssertEqual(summary.finishes, 2)
        XCTAssertEqual(summary.subagentFinishes, 1)
    }

    internal func testSummaryForUnknownProjectIsEmpty() {
        let store = StatsStore(fileURL: fileURL)
        let summary = store.summary(forFolderURL: folder, window: .allTime)
        XCTAssertEqual(summary.assistantMessages, 0)
        XCTAssertEqual(summary.costUSD, 0)
    }

    internal func testWindowFiltering() throws {
        // Seed a stats file with three days at different ages.
        let calendar = Calendar.current
        let todayKey = DayKey.today()
        let threeAgo = DayKey.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: Date())))
        let tenAgo = DayKey.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -10, to: Date())))

        var project = ProjectStat()
        project.days[todayKey] = day(cost: 1, messages: 10, sessions: ["a"])
        project.days[threeAgo] = day(cost: 2, messages: 20, sessions: ["b"])
        project.days[tenAgo] = day(cost: 4, messages: 40, sessions: ["a", "c"])
        var state = StatsState()
        state.projects[folder.standardizedFileURL.path] = project
        try JSONEncoder().encode(state).write(to: fileURL)

        let store = StatsStore(fileURL: fileURL)

        XCTAssertEqual(store.summary(forFolderURL: folder, window: .today).costUSD, 1, accuracy: 0.001)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .last7).costUSD, 3, accuracy: 0.001)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .last30).costUSD, 7, accuracy: 0.001)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).assistantMessages, 70)
        // Distinct sessions union across all days: a, b, c.
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).distinctSessions, 3)
        // Within last 7 days: a, b.
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .last7).distinctSessions, 2)
    }

    internal func testLoadCorruptFileFallsBackToEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        let store = StatsStore(fileURL: fileURL)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).panesOpened, 0)
    }

    internal func testPeakContextIsMaxNotSum() throws {
        let calendar = Calendar.current
        let todayKey = DayKey.today()
        let yesterday = DayKey.key(for: try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date())))
        var project = ProjectStat()
        var todayStat = DayStat()
        todayStat.peakContextTokens = 50_000
        var yesterdayStat = DayStat()
        yesterdayStat.peakContextTokens = 120_000
        project.days[todayKey] = todayStat
        project.days[yesterday] = yesterdayStat
        var state = StatsState()
        state.projects[folder.standardizedFileURL.path] = project
        try JSONEncoder().encode(state).write(to: fileURL)

        let store = StatsStore(fileURL: fileURL)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .last7).peakContextTokens, 120_000)
    }

    deinit {
        // Nothing to release; the temp dir is removed in tearDown.
    }
}
