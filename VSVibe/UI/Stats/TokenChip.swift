import SwiftUI

/// Small labelled token count used in the stats sheet's token breakdown.
internal struct TokenChip: View {
    private enum Layout {
        static let spacing: CGFloat = 1
        static let labelSize: CGFloat = 9
        static let valueSize: CGFloat = 13
    }

    internal let label: String
    internal let value: Int

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(label).font(.system(size: Layout.labelSize, weight: .semibold)).foregroundStyle(.secondary)
            Text(Format.tokens(value)).font(.system(size: Layout.valueSize, weight: .medium, design: .monospaced))
        }
    }
}
