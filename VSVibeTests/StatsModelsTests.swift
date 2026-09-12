import XCTest
@testable import VSVibe

final class StatsModelsTests: XCTestCase {

    // MARK: DayKey

    func testTodayMatchesKeyForNow() {
        XCTAssertEqual(DayKey.today(), DayKey.key(for: Date()))
    }

    func testKeyFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 9
        comps.hour = 13; comps.minute = 30
        let date = Calendar.current.date(from: comps)!
        XCTAssertEqual(DayKey.key(for: date), "2026-05-09")
    }

    func testStartKeyOneDayIsToday() {
        XCTAssertEqual(DayKey.startKey(daysBack: 1), DayKey.today())
    }

    func testStartKeySevenDays() {
        let now = Date()
        let expected = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -6, to: now)!)
        XCTAssertEqual(DayKey.startKey(daysBack: 7, now: now), expected)
    }

    func testDayKeysSortChronologically() {
        XCTAssertTrue("2026-05-09" < "2026-05-10")
        XCTAssertTrue("2026-04-30" < "2026-05-01")
    }

    // MARK: StatWindow

    func testWindowDays() {
        XCTAssertEqual(StatWindow.today.days, 1)
        XCTAssertEqual(StatWindow.last7.days, 7)
        XCTAssertEqual(StatWindow.last30.days, 30)
        XCTAssertNil(StatWindow.allTime.days)
    }

    // MARK: StatsSummary

    func testTotalTokens() {
        var s = StatsSummary()
        s.inputTokens = 1; s.outputTokens = 2; s.cacheCreationTokens = 3; s.cacheReadTokens = 4
        XCTAssertEqual(s.totalTokens, 10)
    }

    func testPeakContextPercentCaps() {
        var s = StatsSummary()
        s.peakContextTokens = 100_000
        XCTAssertEqual(s.peakContextPercent, 50, accuracy: 0.001)
        s.peakContextTokens = 400_000
        XCTAssertEqual(s.peakContextPercent, 100, accuracy: 0.001)
    }

    func testModelSharesSortedByShare() {
        var s = StatsSummary()
        s.modelMessageCounts = ["opus": 3, "sonnet": 1]
        let shares = s.modelShares
        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(shares[0].model, "opus")
        XCTAssertEqual(shares[0].share, 0.75, accuracy: 0.001)
        XCTAssertEqual(shares[1].share, 0.25, accuracy: 0.001)
    }

    func testModelSharesEmptyWhenNoMessages() {
        XCTAssertTrue(StatsSummary().modelShares.isEmpty)
    }

    // MARK: Codable round-trip

    func testStatsStateRoundTrip() throws {
        var day = DayStat()
        day.inputTokens = 42
        day.costUSD = 1.25
        day.modelMessageCounts = ["claude-opus-4-7": 3]
        day.transcriptSessionIds = ["s1", "s2"]
        day.panesOpened = 2
        day.notifications = 1
        var project = ProjectStat()
        project.days["2026-05-22"] = day
        project.transcriptBytes["a.jsonl"] = 1234
        var state = StatsState()
        state.projects["/Users/test/demo"] = project

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(StatsState.self, from: data)

        let d = decoded.projects["/Users/test/demo"]?.days["2026-05-22"]
        XCTAssertEqual(d?.inputTokens, 42)
        XCTAssertEqual(d?.costUSD, 1.25)
        XCTAssertEqual(d?.modelMessageCounts["claude-opus-4-7"], 3)
        XCTAssertEqual(d?.transcriptSessionIds, ["s1", "s2"])
        XCTAssertEqual(d?.panesOpened, 2)
        XCTAssertEqual(decoded.projects["/Users/test/demo"]?.transcriptBytes["a.jsonl"], 1234)
    }

    func testDefaultsAreZero() {
        let day = DayStat()
        XCTAssertEqual(day.inputTokens, 0)
        XCTAssertEqual(day.costUSD, 0)
        XCTAssertEqual(day.toolCalls, 0)
        XCTAssertTrue(day.modelMessageCounts.isEmpty)
        XCTAssertEqual(StatsState().version, StatsState.currentVersion)
    }
}
