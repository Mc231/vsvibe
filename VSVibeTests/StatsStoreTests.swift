import XCTest
@testable import VSVibe

@MainActor
final class StatsStoreTests: XCTestCase {
    private var fileURL: URL!
    private let folder = URL(fileURLWithPath: "/Users/test/projects/demo")

    override func setUp() {
        super.setUp()
        fileURL = TestSupport.makeTempDir("stats").appendingPathComponent("stats.json")
    }

    override func tearDown() {
        TestSupport.remove(fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testRecordPaneOpened() {
        let store = StatsStore(fileURL: fileURL)
        store.recordPaneOpened(folderURL: folder)
        store.recordPaneOpened(folderURL: folder)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .today).panesOpened, 2)
    }

    func testRecordActiveTimeIgnoresNonPositive() {
        let store = StatsStore(fileURL: fileURL)
        store.recordActiveTime(folderURL: folder, seconds: 30)
        store.recordActiveTime(folderURL: folder, seconds: 0)
        store.recordActiveTime(folderURL: folder, seconds: -5)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .today).activeSeconds, 30, accuracy: 0.001)
    }

    func testRecordHookEvents() {
        let store = StatsStore(fileURL: fileURL)
        store.recordHookEvent(folderURL: folder, kind: .notification)
        store.recordHookEvent(folderURL: folder, kind: .stop)
        store.recordHookEvent(folderURL: folder, kind: .stop)
        store.recordHookEvent(folderURL: folder, kind: .subagentStop)
        store.recordHookEvent(folderURL: folder, kind: .unknown) // no-op

        let s = store.summary(forFolderURL: folder, window: .today)
        XCTAssertEqual(s.notifications, 1)
        XCTAssertEqual(s.finishes, 2)
        XCTAssertEqual(s.subagentFinishes, 1)
    }

    func testSummaryForUnknownProjectIsEmpty() {
        let store = StatsStore(fileURL: fileURL)
        let s = store.summary(forFolderURL: folder, window: .allTime)
        XCTAssertEqual(s.assistantMessages, 0)
        XCTAssertEqual(s.costUSD, 0)
    }

    func testWindowFiltering() throws {
        // Seed a stats file with three days at different ages.
        func day(cost: Double, msgs: Int, sessions: [String]) -> DayStat {
            var d = DayStat(); d.costUSD = cost; d.assistantMessages = msgs; d.transcriptSessionIds = sessions
            return d
        }
        let cal = Calendar.current
        let todayKey = DayKey.today()
        let threeAgo = DayKey.key(for: cal.date(byAdding: .day, value: -3, to: Date())!)
        let tenAgo = DayKey.key(for: cal.date(byAdding: .day, value: -10, to: Date())!)

        var project = ProjectStat()
        project.days[todayKey] = day(cost: 1, msgs: 10, sessions: ["a"])
        project.days[threeAgo] = day(cost: 2, msgs: 20, sessions: ["b"])
        project.days[tenAgo] = day(cost: 4, msgs: 40, sessions: ["a", "c"])
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

    func testLoadCorruptFileFallsBackToEmpty() throws {
        try "not json".data(using: .utf8)!.write(to: fileURL)
        let store = StatsStore(fileURL: fileURL)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .allTime).panesOpened, 0)
    }

    func testPeakContextIsMaxNotSum() throws {
        let cal = Calendar.current
        let todayKey = DayKey.today()
        let yesterday = DayKey.key(for: cal.date(byAdding: .day, value: -1, to: Date())!)
        var project = ProjectStat()
        var d1 = DayStat(); d1.peakContextTokens = 50_000
        var d2 = DayStat(); d2.peakContextTokens = 120_000
        project.days[todayKey] = d1
        project.days[yesterday] = d2
        var state = StatsState()
        state.projects[folder.standardizedFileURL.path] = project
        try JSONEncoder().encode(state).write(to: fileURL)

        let store = StatsStore(fileURL: fileURL)
        XCTAssertEqual(store.summary(forFolderURL: folder, window: .last7).peakContextTokens, 120_000)
    }
}
