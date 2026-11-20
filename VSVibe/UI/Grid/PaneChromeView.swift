import SwiftUI

internal struct PaneChromeView: View {
    private enum Layout {
        static let spacing: CGFloat = 8
        static let statusDotSize: CGFloat = 7
        static let titleFontSize: CGFloat = 12
        static let branchSpacing: CGFloat = 3
        static let smallIconSize: CGFloat = 9
        static let detailFontSize: CGFloat = 10
        static let chevronSize: CGFloat = 6
        static let branchOpacity: Double = 0.7
        static let badgeHorizontalPadding: CGFloat = 5
        static let badgeVerticalPadding: CGFloat = 1
        static let badgeOpacity: Double = 0.85
        static let spacerMinLength: CGFloat = 4
        static let menuIconSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 4
        static let gradientTop: Double = 0.16
        static let gradientBottom: Double = 0.12
    }

    @Environment(AppEnvironment.self)
    private var env
    internal let session: TerminalSession
    internal let onClose: () -> Void
    internal let onRestart: () -> Void
    internal let onOpenFreshPane: () -> Void
    internal let onShowStats: () -> Void

    @State private var isBranchSwitcherPresented = false

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            Image(systemName: session.isAlive ? "circle.fill" : "circle")
                .foregroundStyle(statusColor)
                .font(.system(size: Layout.statusDotSize))
                .accessibilityLabel(session.isAlive ? "Running" : "Exited")

            Text(session.folder.displayName)
                .font(.system(size: Layout.titleFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            remoteBadge
            branchButton
            eventIndicator
            statusLabel

            if let usage = session.usage, usage.messageCount > 0 {
                UsageBadge(usage: usage)
            }

            Spacer(minLength: Layout.spacerMinLength)

            trailingControls
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(
            LinearGradient(
                colors: [Color(white: Layout.gradientTop), Color(white: Layout.gradientBottom)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(.white)
    }

    private var statusColor: Color {
        if !session.isAlive {
            return .secondary
        }
        if session.awaitingInput {
            return .orange
        }
        return .green
    }

    /// The SSH host of a remote project's pane.
    @ViewBuilder private var remoteBadge: some View {
        if let remote = session.folder.remote {
            HStack(spacing: Layout.branchSpacing) {
                Image(systemName: "network")
                    .font(.system(size: Layout.smallIconSize, weight: .semibold))
                    .accessibilityHidden(true)
                Text(remote.host)
                    .font(.system(size: Layout.detailFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.white.opacity(Layout.branchOpacity))
            .help("Remote project over SSH: \(remote.location)")
        }
    }

    @ViewBuilder private var branchButton: some View {
        if let branch = session.gitBranch {
            Button {
                isBranchSwitcherPresented = true
            } label: {
                HStack(spacing: Layout.branchSpacing) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: Layout.smallIconSize, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(branch)
                        .font(.system(size: Layout.detailFontSize, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Layout.chevronSize, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white.opacity(Layout.branchOpacity))
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
    }

    @ViewBuilder private var eventIndicator: some View {
        if session.awaitingInput {
            Image(systemName: "bell.fill")
                .font(.system(size: Layout.smallIconSize, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityLabel("Awaiting input")
        } else if session.unreadEventCount > 0 {
            Text("\(session.unreadEventCount)")
                .font(.system(size: Layout.smallIconSize, weight: .semibold, design: .monospaced))
                .padding(.horizontal, Layout.badgeHorizontalPadding)
                .padding(.vertical, Layout.badgeVerticalPadding)
                .background(Capsule().fill(Color.accentColor.opacity(Layout.badgeOpacity)))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        if let label = session.lastEventLabel, session.awaitingInput || session.unreadEventCount > 0 {
            Text(label)
                .font(.system(size: Layout.detailFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if !session.isAlive {
            Text("exited")
                .font(.system(size: Layout.detailFontSize))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var trailingControls: some View {
        if !session.folder.isRemote {
            OpenInMenu(folder: session.folder.url)
                .foregroundStyle(.white)
                .tint(.white)
        }

        Button(action: onRestart) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: Layout.detailFontSize, weight: .semibold))
                .accessibilityLabel("Restart Pane")
        }
        .buttonStyle(.plain)
        .help("Restart Pane")

        optionsMenu

        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: Layout.detailFontSize, weight: .semibold))
                .accessibilityLabel("Close Pane")
        }
        .buttonStyle(.plain)
        .help("Close Pane")
    }

    private var optionsMenu: some View {
        Menu {
            if !session.folder.isRemote {
                Button {
                    env.pendingGitReview = session.folder
                } label: {
                    Label("Review Git Changes…", systemImage: "doc.text.magnifyingglass")
                }
            }
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
                .font(.system(size: Layout.menuIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityLabel("Pane Options")
        }
        .tint(.white)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pane Options")
    }
}
