import SwiftUI

/// Adaptive grid of stat tiles.
internal struct StatGrid<Content: View>: View {
    @ViewBuilder internal let content: Content
    // Generic types cannot hold static stored constants, so layout lives here.
    private let minimumColumnWidth: CGFloat = 150
    private let spacing: CGFloat = 10

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: spacing)]
    }

    internal var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content
        }
    }
}
