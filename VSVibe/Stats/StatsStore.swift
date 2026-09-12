import Foundation
import Observation

/// Owns persisted per-project statistics. Runtime events (pane open/close, hook
/// activity) are recorded synchronously on the main actor; Claude usage is
/// scanned from transcripts off-main and merged back as additive deltas, so a
/// long scan can never clobber concurrently-recorded runtime fields.
@MainActor
@Observable
final class StatsStore {
    private(set) var state: StatsState

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let saveDebouncer = Debouncer(interval: 0.7)

    init(fileURL: URL = AppPaths.statsFile) {
        self.fileURL = fileURL
        self.state = Self.read(from: fileURL)
    }

    // MARK: - Runtime recording

    func recordPaneOpened(folderURL: URL) {
        mutateToday(folderURL) { $0.panesOpened += 1 }
    }

    func recordActiveTime(folderURL: URL, seconds: Double) {
        guard seconds > 0 else { return }
        mutateToday(folderURL) { $0.activeSeconds += seconds }
    }

    func recordHookEvent(folderURL: URL, kind: HookEventKind) {
        mutateToday(folderURL) { day in
            switch kind {
            case .notification: day.notifications += 1
            case .stop: day.finishes += 1
            case .subagentStop: day.subagentFinishes += 1
            case .unknown: break
            }
        }
    }

    // MARK: - Transcript scan

    /// Incrementally folds new transcript bytes for `folderURL` into the store.
    /// File reading/parsing happens off the main actor; only an additive delta
    /// is applied here.
    func scanTranscripts(forFolderURL folderURL: URL) async {
        let path = Self.key(for: folderURL)
        let configDirs = LaunchCommandResolver.hookCapableAliases.compactMap(\.claudeConfigDir)
        let offsets = state.projects[path]?.transcriptBytes ?? [:]

        let delta = await Task.detached { () -> ProjectStat in
            var seed = ProjectStat()
            seed.transcriptBytes = offsets
            TranscriptStatsScanner.scan(into: &seed, folderURL: folderURL, configDirs: configDirs)
            return seed
        }.value

        merge(delta: delta, into: path)
    }

    // MARK: - Queries

    func summary(forFolderURL folderURL: URL, window: StatWindow) -> StatsSummary {
        var summary = StatsSummary()
        guard let stat = state.projects[Self.key(for: folderURL)] else { return summary }

        let dayKeys: [String]
        if let days = window.days {
            let start = DayKey.startKey(daysBack: days)
            dayKeys = stat.days.keys.filter { $0 >= start }
        } else {
            dayKeys = Array(stat.days.keys)
        }

        var sessions = Set<String>()
        for key in dayKeys {
            guard let day = stat.days[key] else { continue }
            summary.costUSD += day.costUSD
            summary.inputTokens += day.inputTokens
            summary.outputTokens += day.outputTokens
            summary.cacheCreationTokens += day.cacheCreationTokens
            summary.cacheReadTokens += day.cacheReadTokens
            summary.assistantMessages += day.assistantMessages
            summary.toolCalls += day.toolCalls
            summary.peakContextTokens = max(summary.peakContextTokens, day.peakContextTokens)
            summary.highContextMessages += day.highContextMessages
            for (model, count) in day.modelMessageCounts {
                summary.modelMessageCounts[model, default: 0] += count
            }
            sessions.formUnion(day.transcriptSessionIds)
            summary.panesOpened += day.panesOpened
            summary.activeSeconds += day.activeSeconds
            summary.notifications += day.notifications
            summary.finishes += day.finishes
            summary.subagentFinishes += day.subagentFinishes
        }
        summary.distinctSessions = sessions.count
        return summary
    }

    // MARK: - Internals

    private func mutateToday(_ folderURL: URL, _ body: (inout DayStat) -> Void) {
        let path = Self.key(for: folderURL)
        let dayKey = DayKey.today()
        var stat = state.projects[path] ?? ProjectStat()
        var day = stat.days[dayKey] ?? DayStat()
        body(&day)
        stat.days[dayKey] = day
        state.projects[path] = stat
        scheduleSave()
    }

    private func merge(delta: ProjectStat, into path: String) {
        var stat = state.projects[path] ?? ProjectStat()
        stat.transcriptBytes = delta.transcriptBytes // scan advances offsets authoritatively
        for (key, d) in delta.days {
            var day = stat.days[key] ?? DayStat()
            day.inputTokens += d.inputTokens
            day.outputTokens += d.outputTokens
            day.cacheCreationTokens += d.cacheCreationTokens
            day.cacheReadTokens += d.cacheReadTokens
            day.costUSD += d.costUSD
            day.assistantMessages += d.assistantMessages
            day.toolCalls += d.toolCalls
            for (model, count) in d.modelMessageCounts {
                day.modelMessageCounts[model, default: 0] += count
            }
            day.peakContextTokens = max(day.peakContextTokens, d.peakContextTokens)
            day.highContextMessages += d.highContextMessages
            for sid in d.transcriptSessionIds where !day.transcriptSessionIds.contains(sid) {
                day.transcriptSessionIds.append(sid)
            }
            stat.days[key] = day
        }
        state.projects[path] = stat
        scheduleSave()
    }

    private static func key(for folderURL: URL) -> String {
        folderURL.standardizedFileURL.path
    }

    private func scheduleSave() {
        let snapshot = state
        let url = fileURL
        saveDebouncer.call {
            Self.write(snapshot, to: url)
        }
    }

    private static func read(from url: URL) -> StatsState {
        guard FileManager.default.fileExists(atPath: url.path) else { return StatsState() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StatsState.self, from: data)
        } catch {
            Log.store.error("Failed to load stats: \(String(describing: error), privacy: .public)")
            return StatsState()
        }
    }

    private static func write(_ state: StatsState, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            Log.store.error("Failed to save stats: \(String(describing: error), privacy: .public)")
        }
    }
}
