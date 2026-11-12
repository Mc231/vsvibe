import SwiftUI

/// Selectable color circle used by the label editor's color picker.
internal struct ColorSwatch: View {
    private enum Layout {
        static let diameter: CGFloat = 20
        static let selectedRingOpacity: Double = 0.8
        static let ringWidth: CGFloat = 2
        static let ringOutset: CGFloat = -3
        static let padding: CGFloat = 4
    }

    internal let hex: String
    internal let isSelected: Bool
    internal let action: () -> Void

    internal var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(labelHex: hex))
                .frame(width: Layout.diameter, height: Layout.diameter)
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.primary.opacity(isSelected ? Layout.selectedRingOpacity : 0.0),
                            lineWidth: Layout.ringWidth
                        )
                        .padding(Layout.ringOutset)
                )
                // Keep the selection ring inside the swatch's own bounds so it
                // never clips against the sheet edge.
                .padding(Layout.padding)
        }
        .buttonStyle(.plain)
        .help(hex)
    }
}
