import SwiftUI

/// One project row in the sidebar: name, launch command badge, label dots,
/// activity indicator and the continue / open buttons.
internal struct SidebarRow: View {
    private enum Layout {
        static let spacing: CGFloat = 8
        static let textSpacing: CGFloat = 1
        static let titleSpacing: CGFloat = 6
        static let badgeFontSize: CGFloat = 9
        static let badgeHorizontalPadding: CGFloat = 5
        static let badgeVerticalPadding: CGFloat = 1
        static let badgeOpacity: Double = 0.18
        static let dotSpacing: CGFloat = 2
        static let labelDotSize: CGFloat = 5
        static let activityDotSize: CGFloat = 6
        static let inactiveDotOpacity: Double = 0.3
        static let buttonIconSize: CGFloat = 10
        static let buttonSize: CGFloat = 18
        static let dimmedOpacity: Double = 0.55
        static let verticalPadding: CGFloat = 2
    }

    internal let folder: FolderEntry
    /// Every label on this project, used to hint at cross-section membership.
    internal let labels: [ProjectLabel]
    /// The section this row is rendered in (nil for the unlabelled bucket).
    internal let currentLabelID: ProjectLabel.ID?
    internal let isActive: Bool
    internal let onOpenOrFocus: () -> Void
    internal let onContinue: () -> Void

    @State private var isHovering = false

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                titleLine
                Text(folder.url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(Layout.inactiveDotOpacity))
                .frame(width: Layout.activityDotSize, height: Layout.activityDotSize)
            if !isActive {
                continueButton
            }
            openButton
        }
        .padding(.vertical, Layout.verticalPadding)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    /// Labels other than the section we're in — the project also appears there.
    private var otherLabels: [ProjectLabel] {
        labels.filter { $0.id != currentLabelID }
    }

    private var titleLine: some View {
        HStack(spacing: Layout.titleSpacing) {
            Text(folder.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            if folder.launchCommand != LaunchCommandResolver.defaultCommand {
                Text(folder.launchCommand)
                    .font(.system(size: Layout.badgeFontSize, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, Layout.badgeHorizontalPadding)
                    .padding(.vertical, Layout.badgeVerticalPadding)
                    .background(Color.accentColor.opacity(Layout.badgeOpacity))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            if !otherLabels.isEmpty {
                HStack(spacing: Layout.dotSpacing) {
                    ForEach(otherLabels) { label in
                        Circle()
                            .fill(label.color)
                            .frame(width: Layout.labelDotSize, height: Layout.labelDotSize)
                    }
                }
                .help("Also in " + otherLabels.map(\.name).joined(separator: ", "))
            }
        }
    }

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: Layout.buttonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
                .accessibilityLabel("Continue Last Session")
        }
        .buttonStyle(.borderless)
        .opacity(isHovering ? 1.0 : Layout.dimmedOpacity)
        .help("Continue Last Session (\(LaunchCommandResolver.continueCommand(for: folder.launchCommand)))")
    }

    private var openButton: some View {
        Button {
            onOpenOrFocus()
        } label: {
            Image(systemName: isActive ? "arrow.up.right.square" : "play.fill")
                .font(.system(size: Layout.buttonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
                .accessibilityLabel(isActive ? "Focus Pane" : "Open Pane")
        }
        .buttonStyle(.borderless)
        .opacity(isHovering || isActive ? 1.0 : Layout.dimmedOpacity)
        .help(isActive ? "Focus Pane" : "Open Pane")
    }
}
