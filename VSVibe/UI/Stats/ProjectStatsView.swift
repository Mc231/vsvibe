import SwiftUI

/// Per-project statistics sheet. Claude/activity figures come from the persisted
/// `StatsStore` (transcript-scanned + runtime-recorded) and follow the window
/// picker; git figures are computed on demand over a fixed 30-day window.
internal struct ProjectStatsView: View {
    private enum Layout {
        static let sectionSpacing: CGFloat = 22
        static let contentPadding: CGFloat = 20
        static let width: CGFloat = 540
        static let height: CGFloat = 620
        static let titleSpacing: CGFloat = 2
        static let headerPadding: CGFloat = 16
        static let claudeSpacing: CGFloat = 12
        static let progressSpacing: CGFloat = 6
        static let breakdownSpacing: CGFloat = 4
        static let chipSpacing: CGFloat = 14
        static let modelSpacing: CGFloat = 6
        static let modelRowSpacing: CGFloat = 8
        static let modelFontSize: CGFloat = 11
        static let modelNameWidth: CGFloat = 90
        static let barTrackOpacity: Double = 0.15
        static let barFillOpacity: Double = 0.7
        static let barMinWidth: CGFloat = 4
        static let barHeight: CGFloat = 8
        static let percentMultiplier: Double = 100
        static let percentWidth: CGFloat = 36
        static let subjectFontSize: CGFloat = 12
        static let subjectLineLimit = 2
    }

    /// Fixed window for the on-demand git statistics.
    private static let gitWindowDays = 30

    internal let folder: FolderEntry
    internal let onClose: () -> Void

    @Environment(AppEnvironment.self)
    private var env

    @State private var window: StatWindow = .last7
    @State private var gitStats: GitStats?
    @State private var isScanning = true

    internal var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    claudeSection
                    activitySection
                    gitSection
                }
                .padding(Layout.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Layout.width, height: Layout.height)
        .task { await refresh() }
    }

    private var summary: StatsSummary {
        env.statsStore.summary(forFolderURL: folder.url, window: window)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(folder.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(folder.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Layout.headerPadding)
    }

    // MARK: - Claude usage

    private var claudeSection: some View {
        let stats = summary
        return Section {
            VStack(alignment: .leading, spacing: Layout.claudeSpacing) {
                Picker("", selection: $window) {
                    ForEach(StatWindow.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                claudeGrid(stats)

                if stats.totalTokens > 0 {
                    tokenBreakdown(stats)
                }
                if !stats.modelShares.isEmpty {
                    modelSplit(stats)
                }
                if isScanning && stats.assistantMessages == 0 {
                    HStack(spacing: Layout.progressSpacing) {
                        ProgressView().controlSize(.small)
                        Text("Scanning transcripts…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            StatsSectionHeader(title: "Claude Usage", systemImage: "sparkles")
        }
    }

    // MARK: - Activity (lifecycle + hooks)

    private var activitySection: some View {
        let stats = summary
        return Section {
            StatGrid {
                StatTile(title: "Panes opened", value: "\(stats.panesOpened)")
                StatTile(title: "Time open", value: Format.duration(stats.activeSeconds))
                StatTile(title: "Finishes", value: "\(stats.finishes)")
                StatTile(title: "Needs input", value: "\(stats.notifications)")
                StatTile(title: "Subagents", value: "\(stats.subagentFinishes)")
            }
        } header: {
            StatsSectionHeader(title: "Activity", systemImage: "bolt.fill")
        }
    }

    // MARK: - Git

    @ViewBuilder private var gitSection: some View {
        Section {
            if let git = gitStats {
                if git.isRepo {
                    gitGrid(git)
                    if let date = git.lastCommitDate {
                        VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                            Text("Last commit \(Format.relative(date))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let subject = git.lastCommitSubject, !subject.isEmpty {
                                Text(subject)
                                    .font(.system(size: Layout.subjectFontSize))
                                    .lineLimit(Layout.subjectLineLimit)
                            }
                        }
                    }
                } else {
                    Text("Not a git repository").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                HStack(spacing: Layout.progressSpacing) {
                    ProgressView().controlSize(.small)
                    Text("Reading git…").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            StatsSectionHeader(title: "Git", systemImage: "arrow.triangle.branch")
        }
    }

    private func claudeGrid(_ stats: StatsSummary) -> some View {
        StatGrid {
            StatTile(title: "Cost", value: Format.cost(stats.costUSD), accent: true)
            StatTile(title: "Tokens", value: Format.tokens(stats.totalTokens))
            StatTile(title: "Messages", value: "\(stats.assistantMessages)")
            StatTile(title: "Tool calls", value: "\(stats.toolCalls)")
            StatTile(title: "Sessions", value: "\(stats.distinctSessions)")
            StatTile(
                title: "Peak context",
                value: String(format: "%.0f%%", stats.peakContextPercent),
                subtitle: stats.highContextMessages > 0 ? "\(stats.highContextMessages) msgs ≥85%" : nil
            )
        }
    }

    private func tokenBreakdown(_ stats: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: Layout.breakdownSpacing) {
            Text("Token breakdown").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Layout.chipSpacing) {
                TokenChip(label: "In", value: stats.inputTokens)
                TokenChip(label: "Out", value: stats.outputTokens)
                TokenChip(label: "Cache W", value: stats.cacheCreationTokens)
                TokenChip(label: "Cache R", value: stats.cacheReadTokens)
            }
        }
    }

    private func modelSplit(_ stats: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: Layout.modelSpacing) {
            Text("Models").font(.caption).foregroundStyle(.secondary)
            ForEach(stats.modelShares, id: \.model) { item in
                HStack(spacing: Layout.modelRowSpacing) {
                    Text(Format.model(item.model))
                        .font(.system(size: Layout.modelFontSize, design: .monospaced))
                        .frame(width: Layout.modelNameWidth, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(Layout.barTrackOpacity))
                            Capsule()
                                .fill(Color.accentColor.opacity(Layout.barFillOpacity))
                                .frame(width: max(Layout.barMinWidth, geo.size.width * item.share))
                        }
                    }
                    .frame(height: Layout.barHeight)
                    Text(String(format: "%.0f%%", item.share * Layout.percentMultiplier))
                        .font(.system(size: Layout.modelFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: Layout.percentWidth, alignment: .trailing)
                }
            }
        }
    }

    private func gitGrid(_ git: GitStats) -> some View {
        StatGrid {
            StatTile(title: "Branch", value: git.currentBranch ?? "—")
            StatTile(title: "Branches", value: "\(git.branchCount)")
            StatTile(title: "Commits", value: "\(git.commitsInWindow)", subtitle: "last \(git.windowDays)d")
            StatTile(title: "Lines", value: "+\(git.linesAdded) −\(git.linesRemoved)")
            StatTile(title: "Files", value: "\(git.filesTouched)", subtitle: "last \(git.windowDays)d")
            StatTile(
                title: "Upstream",
                value: aheadBehindLabel(git),
                subtitle: git.ahead == nil ? "no upstream" : nil
            )
        }
    }

    private func aheadBehindLabel(_ git: GitStats) -> String {
        guard let ahead = git.ahead, let behind = git.behind else {
            return "—"
        }
        if ahead == 0 && behind == 0 {
            return "up to date"
        }
        return "↑\(ahead) ↓\(behind)"
    }

    // MARK: - Loading

    private func refresh() async {
        isScanning = true
        await env.statsStore.scanTranscripts(forFolderURL: folder.url)
        isScanning = false
        let url = folder.url
        let windowDays = Self.gitWindowDays
        gitStats = await Task.detached { GitInfo.collectStats(forFolder: url, windowDays: windowDays) }.value
    }
}
