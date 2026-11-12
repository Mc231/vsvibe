@testable import VSVibe
import XCTest

internal final class StatsModelsTests: XCTestCase {
    // MARK: DayKey

    internal func testTodayMatchesKeyForNow() {
        XCTAssertEqual(DayKey.today(), DayKey.key(for: Date()))
    }

    internal func testKeyFormat() throws {
        var comps = DateComponents()
        comps.year = 2_026
        comps.month = 5
        comps.day = 9
        comps.hour = 13
        comps.minute = 30
        let date = try XCTUnwrap(Calendar.current.date(from: comps))
        XCTAssertEqual(DayKey.key(for: date), "2026-05-09")
    }

    internal func testStartKeyOneDayIsToday() {
        XCTAssertEqual(DayKey.startKey(daysBack: 1), DayKey.today())
    }

    internal func testStartKeySevenDays() throws {
        let now = Date()
        let expected = DayKey.key(for: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -6, to: now)))
        XCTAssertEqual(DayKey.startKey(daysBack: 7, now: now), expected)
    }

    internal func testDayKeysSortChronologically() {
        XCTAssertTrue("2026-05-09" < "2026-05-10")
        XCTAssertTrue("2026-04-30" < "2026-05-01")
    }

    // MARK: StatWindow

    internal func testWindowDays() {
        XCTAssertEqual(StatWindow.today.days, 1)
        XCTAssertEqual(StatWindow.last7.days, 7)
        XCTAssertEqual(StatWindow.last30.days, 30)
        XCTAssertNil(StatWindow.allTime.days)
    }

    // MARK: StatsSummary

    internal func testTotalTokens() {
        var summary = StatsSummary()
        summary.inputTokens = 1
        summary.outputTokens = 2
        summary.cacheCreationTokens = 3
        summary.cacheReadTokens = 4
        XCTAssertEqual(summary.totalTokens, 10)
    }

    internal func testPeakContextPercentCaps() {
        var summary = StatsSummary()
        summary.peakContextTokens = 100_000
        XCTAssertEqual(summary.peakContextPercent, 50, accuracy: 0.001)
        summary.peakContextTokens = 400_000
        XCTAssertEqual(summary.peakContextPercent, 100, accuracy: 0.001)
    }

    internal func testModelSharesSortedByShare() {
        var summary = StatsSummary()
        summary.modelMessageCounts = ["opus": 3, "sonnet": 1]
        let shares = summary.modelShares
        XCTAssertEqual(shares.count, 2)
        XCTAssertEqual(shares[0].model, "opus")
        XCTAssertEqual(shares[0].share, 0.75, accuracy: 0.001)
        XCTAssertEqual(shares[1].share, 0.25, accuracy: 0.001)
    }

    internal func testModelSharesEmptyWhenNoMessages() {
        XCTAssertTrue(StatsSummary().modelShares.isEmpty)
    }

    // MARK: Codable round-trip

    internal func testStatsStateRoundTrip() throws {
        var day = DayStat()
        day.inputTokens = 42
        day.costUSD = 1.25
        day.modelMessageCounts = ["claude-opus-4-7": 3]
        day.transcriptSessionIds = ["s1", "s2"]
        day.panesOpened = 2
        day.notifications = 1
        var project = ProjectStat()
        project.days["2026-05-22"] = day
        project.transcriptBytes["a.jsonl"] = 1_234
        var state = StatsState()
        state.projects["/Users/test/demo"] = project

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(StatsState.self, from: data)

        let decodedDay = decoded.projects["/Users/test/demo"]?.days["2026-05-22"]
        XCTAssertEqual(decodedDay?.inputTokens, 42)
        XCTAssertEqual(decodedDay?.costUSD, 1.25)
        XCTAssertEqual(decodedDay?.modelMessageCounts["claude-opus-4-7"], 3)
        XCTAssertEqual(decodedDay?.transcriptSessionIds, ["s1", "s2"])
        XCTAssertEqual(decodedDay?.panesOpened, 2)
        XCTAssertEqual(decoded.projects["/Users/test/demo"]?.transcriptBytes["a.jsonl"], 1_234)
    }

    internal func testDefaultsAreZero() {
        let day = DayStat()
        XCTAssertEqual(day.inputTokens, 0)
        XCTAssertEqual(day.costUSD, 0)
        XCTAssertEqual(day.toolCalls, 0)
        XCTAssertTrue(day.modelMessageCounts.isEmpty)
        XCTAssertEqual(StatsState().version, StatsState.currentVersion)
    }

    deinit {
        // Nothing to release.
    }
}
