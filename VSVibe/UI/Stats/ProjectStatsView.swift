import SwiftUI

/// Per-project statistics sheet. Claude/activity figures come from the persisted
/// `StatsStore` (transcript-scanned + runtime-recorded) and follow the window
/// picker; git figures are computed on demand over a fixed 30-day window.
struct ProjectStatsView: View {
    let folder: FolderEntry
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var window: StatWindow = .last7
    @State private var gitStats: GitStats?
    @State private var isScanning = true

    private var summary: StatsSummary {
        env.statsStore.summary(forFolderURL: folder.url, window: window)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    claudeSection
                    activitySection
                    gitSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 540, height: 620)
        .task { await refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(.title2).fontWeight(.semibold)
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
        .padding(16)
    }

    // MARK: - Claude usage

    private var claudeSection: some View {
        let s = summary
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $window) {
                    ForEach(StatWindow.allCases) { w in
                        Text(w.label).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                StatGrid {
                    StatTile(title: "Cost", value: Format.cost(s.costUSD), accent: true)
                    StatTile(title: "Tokens", value: Format.tokens(s.totalTokens))
                    StatTile(title: "Messages", value: "\(s.assistantMessages)")
                    StatTile(title: "Tool calls", value: "\(s.toolCalls)")
                    StatTile(title: "Sessions", value: "\(s.distinctSessions)")
                    StatTile(title: "Peak context", value: String(format: "%.0f%%", s.peakContextPercent),
                             subtitle: s.highContextMessages > 0 ? "\(s.highContextMessages) msgs ≥85%" : nil)
                }

                if s.totalTokens > 0 {
                    tokenBreakdown(s)
                }
                if !s.modelShares.isEmpty {
                    modelSplit(s)
                }
                if isScanning && s.assistantMessages == 0 {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Scanning transcripts…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            SectionHeader(title: "Claude Usage", systemImage: "sparkles")
        }
    }

    private func tokenBreakdown(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Token breakdown").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                TokenChip(label: "In", value: s.inputTokens)
                TokenChip(label: "Out", value: s.outputTokens)
                TokenChip(label: "Cache W", value: s.cacheCreationTokens)
                TokenChip(label: "Cache R", value: s.cacheReadTokens)
            }
        }
    }

    private func modelSplit(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models").font(.caption).foregroundStyle(.secondary)
            ForEach(s.modelShares, id: \.model) { item in
                HStack(spacing: 8) {
                    Text(Format.model(item.model))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule().fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(4, geo.size.width * item.share))
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.0f%%", item.share * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Activity (lifecycle + hooks)

    private var activitySection: some View {
        let s = summary
        return Section {
            StatGrid {
                StatTile(title: "Panes opened", value: "\(s.panesOpened)")
                StatTile(title: "Time open", value: Format.duration(s.activeSeconds))
                StatTile(title: "Finishes", value: "\(s.finishes)")
                StatTile(title: "Needs input", value: "\(s.notifications)")
                StatTile(title: "Subagents", value: "\(s.subagentFinishes)")
            }
        } header: {
            SectionHeader(title: "Activity", systemImage: "bolt.fill")
        }
    }

    // MARK: - Git

    @ViewBuilder
    private var gitSection: some View {
        Section {
            if let git = gitStats {
                if git.isRepo {
                    StatGrid {
                        StatTile(title: "Branch", value: git.currentBranch ?? "—")
                        StatTile(title: "Branches", value: "\(git.branchCount)")
                        StatTile(title: "Commits", value: "\(git.commitsInWindow)", subtitle: "last \(git.windowDays)d")
                        StatTile(title: "Lines", value: "+\(git.linesAdded) −\(git.linesRemoved)")
                        StatTile(title: "Files", value: "\(git.filesTouched)", subtitle: "last \(git.windowDays)d")
                        StatTile(title: "Upstream",
                                 value: aheadBehindLabel(git),
                                 subtitle: git.ahead == nil ? "no upstream" : nil)
                    }
                    if let date = git.lastCommitDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last commit \(Format.relative(date))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let subject = git.lastCommitSubject, !subject.isEmpty {
                                Text(subject).font(.system(size: 12)).lineLimit(2)
                            }
                        }
                    }
                } else {
                    Text("Not a git repository").foregroundStyle(.secondary).font(.callout)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading git…").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            SectionHeader(title: "Git", systemImage: "arrow.triangle.branch")
        }
    }

    private func aheadBehindLabel(_ git: GitStats) -> String {
        guard let ahead = git.ahead, let behind = git.behind else { return "—" }
        if ahead == 0 && behind == 0 { return "up to date" }
        return "↑\(ahead) ↓\(behind)"
    }

    // MARK: - Loading

    private func refresh() async {
        isScanning = true
        await env.statsStore.scanTranscripts(forFolderURL: folder.url)
        isScanning = false
        let url = folder.url
        gitStats = await Task.detached { GitInfo.collectStats(forFolder: url, windowDays: 30) }.value
    }
}

// MARK: - Reusable pieces

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.bottom, 2)
    }
}

private struct StatGrid<Content: View>: View {
    @ViewBuilder let content: Content
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            content
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String?
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subtitle {
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

private struct TokenChip: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(Format.tokens(value)).font(.system(size: 13, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Formatting

enum Format {
    static func cost(_ usd: Double) -> String {
        if usd >= 100 { return String(format: "$%.0f", usd) }
        return String(format: "$%.2f", usd)
    }

    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3_600
        let m = (total % 3_600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// `claude-opus-4-7` → `Opus 4.7`.
    static func model(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
        let parts = s.split(separator: "-")
        guard let family = parts.first else { return raw }
        let version = parts.dropFirst().joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
