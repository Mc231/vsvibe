import SwiftUI

/// Toggleable label capsule used by the project editor's label picker.
internal struct LabelChip: View {
    private enum Layout {
        static let spacing: CGFloat = 4
        static let iconSize: CGFloat = 9
        static let textSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 3
        static let selectedFillOpacity: Double = 0.22
        static let idleFillOpacity: Double = 0.10
        static let selectedBorderOpacity: Double = 0.55
        static let borderWidth: CGFloat = 1
    }

    internal let label: ProjectLabel
    internal let isSelected: Bool
    internal let action: () -> Void

    internal var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.spacing) {
                Image(systemName: label.symbolName)
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .accessibilityHidden(true)
                Text(label.name)
                    .font(.system(size: Layout.textSize, weight: .semibold))
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(
                Capsule().fill(label.color.opacity(isSelected ? Layout.selectedFillOpacity : Layout.idleFillOpacity))
            )
            .foregroundStyle(isSelected ? label.color : Color.secondary)
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? label.color.opacity(Layout.selectedBorderOpacity) : Color.clear,
                    lineWidth: Layout.borderWidth
                )
            )
        }
        .buttonStyle(.plain)
    }
}
