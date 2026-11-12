import SwiftUI

/// Section title in the stats sheet.
internal struct StatsSectionHeader: View {
    private enum Layout {
        static let bottomPadding: CGFloat = 2
    }

    internal let title: String
    internal let systemImage: String

    internal var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.bottom, Layout.bottomPadding)
    }
}
