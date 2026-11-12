import SwiftUI

struct TilingGridView<Content: View>: View {
    let sessions: [TerminalSession]
    @ViewBuilder let content: (TerminalSession) -> Content

    var body: some View {
        TileLayout(count: sessions.count) {
            ForEach(sessions) { session in
                content(session)
            }
        }
    }
}

struct TileLayout: Layout {
    let count: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 800, height: 600))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let n = subviews.count
        guard n > 0 else { return }

        let cols = max(1, Int(ceil(sqrt(Double(n)))))
        let rows = max(1, Int(ceil(Double(n) / Double(cols))))
        let fullRows = n / cols
        let remainder = n - fullRows * cols

        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)

        for r in 0..<fullRows {
            for c in 0..<cols {
                let idx = r * cols + c
                let x = bounds.minX + CGFloat(c) * cellW
                let y = bounds.minY + CGFloat(r) * cellH
                let size = CGSize(width: cellW, height: cellH)
                subviews[idx].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                    proposal: ProposedViewSize(size))
            }
        }

        if remainder > 0 {
            let lastCellW = bounds.width / CGFloat(remainder)
            let y = bounds.minY + CGFloat(fullRows) * cellH
            for c in 0..<remainder {
                let idx = fullRows * cols + c
                let x = bounds.minX + CGFloat(c) * lastCellW
                let size = CGSize(width: lastCellW, height: cellH)
                subviews[idx].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                    proposal: ProposedViewSize(size))
            }
        }
    }
}
