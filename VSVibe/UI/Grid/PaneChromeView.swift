import SwiftUI

struct PaneChromeView: View {
    let session: TerminalSession
    let onClose: () -> Void
    let onRestart: () -> Void
    let onOpenFreshPane: () -> Void
    let onShowStats: () -> Void

    @State private var isBranchSwitcherPresented = false

    private var statusColor: Color {
        if !session.isAlive { return .secondary }
        if session.awaitingInput { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isAlive ? "circle.fill" : "circle")
                .foregroundStyle(statusColor)
                .font(.system(size: 7))

            Text(session.folder.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if let branch = session.gitBranch {
                Button {
                    isBranchSwitcherPresented = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .semibold))
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch git branch (current: \(branch))")
                .popover(isPresented: $isBranchSwitcherPresented, arrowEdge: .bottom) {
                    BranchSwitcher(folderURL: session.folder.url, currentBranch: branch) { newBranch in
                        session.gitBranch = newBranch
                    }
                }
            }

            if session.awaitingInput {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
            } else if session.unreadEventCount > 0 {
                Text("\(session.unreadEventCount)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
                    .foregroundStyle(.white)
            }

            if let label = session.lastEventLabel, session.awaitingInput || session.unreadEventCount > 0 {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if !session.isAlive {
                Text("exited")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let usage = session.usage, usage.messageCount > 0 {
                UsageBadge(usage: usage)
            }

            Spacer(minLength: 4)

            OpenInMenu(folder: session.folder.url)
                .foregroundStyle(.white)
                .tint(.white)

            Button(action: onRestart) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Restart Pane")

            Menu {
                Button {
                    onOpenFreshPane()
                } label: {
                    Label("Open Fresh Pane", systemImage: "square.on.square")
                }
                .help("Open a second pane for the same folder with a fresh session.")
                Button {
                    onShowStats()
                } label: {
                    Label("Project Stats…", systemImage: "chart.bar")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .tint(.white)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pane Options")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close Pane")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(.white)
    }
}

private struct UsageBadge: View {
    let usage: SessionUsage

    private var pctColor: Color {
        switch usage.contextPercent {
        case 0..<60: return .green
        case 60..<85: return .yellow
        default: return .red
        }
    }

    private var totalTokensLabel: String {
        let n = usage.totalInput + usage.totalOutput + usage.totalCacheCreation + usage.totalCacheRead
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1000 {
            return String(format: "%.0fk", Double(n) / 1000)
        }
        return "\(n)"
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 9, weight: .semibold))
                Text(String(format: "%.0f%%", usage.contextPercent))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(pctColor)

            Text(totalTokensLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))

            if usage.estimatedCostUSD >= 0.01 {
                Text(String(format: "$%.2f", usage.estimatedCostUSD))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .help("Context \(Int(usage.contextPercent))% of \(usage.contextWindow.formatted()) · \(usage.messageCount) msgs")
    }
}
