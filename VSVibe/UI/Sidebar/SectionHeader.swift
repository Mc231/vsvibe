import SwiftUI

/// Sidebar section header: label icon, title and project count.
internal struct SectionHeader: View {
    private enum Layout {
        static let spacing: CGFloat = 6
        static let fontSize: CGFloat = 10
    }

    internal let group: SidebarGroup

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            if let label = group.label {
                Image(systemName: label.symbolName)
                    .font(.system(size: Layout.fontSize, weight: .semibold))
                    .foregroundStyle(label.color)
                    .accessibilityHidden(true)
            }
            Text(group.title)
            if !group.folders.isEmpty {
                Text("\(group.folders.count)")
                    .font(.system(size: Layout.fontSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
