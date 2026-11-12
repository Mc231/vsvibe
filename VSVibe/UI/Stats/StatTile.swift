import SwiftUI

/// A single titled figure in the stats sheet.
internal struct StatTile: View {
    private enum Layout {
        static let spacing: CGFloat = 2
        static let captionSize: CGFloat = 9
        static let valueSize: CGFloat = 18
        static let minimumScaleFactor: CGFloat = 0.6
        static let padding: CGFloat = 10
        static let cornerRadius: CGFloat = 8
        static let backgroundOpacity: Double = 0.08
    }

    internal let title: String
    internal let value: String
    internal var subtitle: String?
    internal var accent: Bool = false

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(title.uppercased())
                .font(.system(size: Layout.captionSize, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: Layout.valueSize, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(Layout.minimumScaleFactor)
            if let subtitle {
                Text(subtitle).font(.system(size: Layout.captionSize)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.padding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(Color.secondary.opacity(Layout.backgroundOpacity))
        )
    }
}
