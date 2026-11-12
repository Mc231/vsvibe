import SwiftUI

/// Yellow banner shown above a pane's terminal when its session reports an error.
internal struct PaneWarningBanner: View {
    private enum Layout {
        static let spacing: CGFloat = 8
        static let fontSize: CGFloat = 11
        static let messageLineLimit = 2
        static let spacerMinLength: CGFloat = 4
        static let dismissIconSize: CGFloat = 9
        static let dismissIconOpacity: Double = 0.7
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let backgroundOpacity: Double = 0.14
    }

    internal let message: String
    internal let onEditProject: () -> Void
    internal let onDismiss: () -> Void

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Layout.fontSize))
                .foregroundStyle(.yellow)
                .accessibilityLabel("Warning")
            Text(message)
                .font(.system(size: Layout.fontSize))
                .foregroundStyle(.white)
                .lineLimit(Layout.messageLineLimit)
            Spacer(minLength: Layout.spacerMinLength)
            Button("Edit Project…", action: onEditProject)
                .buttonStyle(.borderless)
                .font(.system(size: Layout.fontSize, weight: .semibold))
                .foregroundStyle(.yellow)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Layout.dismissIconSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(Layout.dismissIconOpacity))
                    .accessibilityLabel("Dismiss")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Color.yellow.opacity(Layout.backgroundOpacity))
    }
}
