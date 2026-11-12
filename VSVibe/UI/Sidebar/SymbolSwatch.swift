import SwiftUI

/// Selectable SF Symbol tile used by the label editor's icon picker.
internal struct SymbolSwatch: View {
    private enum Layout {
        static let iconSize: CGFloat = 13
        static let width: CGFloat = 30
        static let height: CGFloat = 26
        static let cornerRadius: CGFloat = 6
        static let selectedOpacity: Double = 0.18
        static let idleOpacity: Double = 0.10
    }

    internal let symbol: String
    internal let tint: Color
    internal let isSelected: Bool
    internal let action: () -> Void

    internal var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Layout.iconSize))
                .foregroundStyle(isSelected ? tint : Color.secondary)
                .frame(width: Layout.width, height: Layout.height)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cornerRadius)
                        .fill(
                            isSelected
                                ? tint.opacity(Layout.selectedOpacity)
                                : Color.secondary.opacity(Layout.idleOpacity)
                        )
                )
                .accessibilityLabel(symbol)
        }
        .buttonStyle(.plain)
    }
}
