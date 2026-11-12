import SwiftUI

/// Lays out panes in a near-square grid; the last, partially filled row
/// stretches its cells to use the full width.
internal struct TileLayout: Layout {
    private enum Defaults {
        static let fallbackWidth: CGFloat = 800
        static let fallbackHeight: CGFloat = 600
        static let fallbackSize = CGSize(width: fallbackWidth, height: fallbackHeight)
    }

    internal func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: Defaults.fallbackSize)
    }

    internal func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let total = subviews.count
        guard total > 0 else {
            return
        }

        let cols = max(1, Int(ceil(sqrt(Double(total)))))
        let rows = max(1, Int(ceil(Double(total) / Double(cols))))
        let fullRows = total / cols
        let remainder = total - fullRows * cols

        let cellWidth = bounds.width / CGFloat(cols)
        let cellHeight = bounds.height / CGFloat(rows)

        for row in 0..<fullRows {
            for col in 0..<cols {
                let index = row * cols + col
                let originX = bounds.minX + CGFloat(col) * cellWidth
                let originY = bounds.minY + CGFloat(row) * cellHeight
                let size = CGSize(width: cellWidth, height: cellHeight)
                subviews[index].place(
                    at: CGPoint(x: originX, y: originY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
            }
        }

        if remainder > 0 {
            let lastCellWidth = bounds.width / CGFloat(remainder)
            let originY = bounds.minY + CGFloat(fullRows) * cellHeight
            for col in 0..<remainder {
                let index = fullRows * cols + col
                let originX = bounds.minX + CGFloat(col) * lastCellWidth
                let size = CGSize(width: lastCellWidth, height: cellHeight)
                subviews[index].place(
                    at: CGPoint(x: originX, y: originY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
            }
        }
    }
}
