import SwiftUI

/// One line of the hook setup window's status list: an icon, a label and a
/// monospaced detail.
internal struct HookStatusRow: View {
    private enum Layout {
        static let spacing: CGFloat = 10
        static let titleSpacing: CGFloat = 2
        static let iconSize: CGFloat = 16
        static let labelSize: CGFloat = 12
        static let detailSize: CGFloat = 11
        static let detailLineLimit = 2
    }

    internal let label: String
    internal let detail: String
    internal let isOK: Bool
    internal var iconOverride: String?
    internal var iconColor: Color?

    internal var body: some View {
        HStack(alignment: .top, spacing: Layout.spacing) {
            Image(systemName: iconOverride ?? (isOK ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(iconColor ?? (isOK ? Color.green : Color.secondary))
                .font(.system(size: Layout.iconSize))
                .accessibilityLabel(isOK ? "Installed" : "Not installed")
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(label).font(.system(size: Layout.labelSize, weight: .semibold))
                Text(detail)
                    .font(.system(size: Layout.detailSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(Layout.detailLineLimit)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}
