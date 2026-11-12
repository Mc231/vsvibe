import SwiftUI

/// Selectable launch-command capsule used by the project editor.
internal struct CommandChip: View {
    private enum Layout {
        static let textSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 3
        static let selectedFillOpacity: Double = 0.22
        static let idleFillOpacity: Double = 0.12
        static let selectedBorderOpacity: Double = 0.5
        static let borderWidth: CGFloat = 1
    }

    internal let text: String
    internal let isSelected: Bool
    internal let action: () -> Void

    internal var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: Layout.textSize, weight: .semibold, design: .monospaced))
                .padding(.horizontal, Layout.horizontalPadding)
                .padding(.vertical, Layout.verticalPadding)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color.accentColor.opacity(Layout.selectedFillOpacity)
                            : Color.secondary.opacity(Layout.idleFillOpacity)
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accentColor.opacity(Layout.selectedBorderOpacity) : Color.clear,
                        lineWidth: Layout.borderWidth
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
