import SwiftUI

/// Left-aligned layout that wraps its subviews onto new lines instead of
/// overflowing horizontally. Used for the label color/icon pickers and the
/// label chips, whose item count is user-driven and can exceed one line.
internal struct FlowLayout: Layout {
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private enum Defaults {
        static let spacing: CGFloat = 6
        static let centeringDivisor: CGFloat = 2
    }

    internal var spacing: CGFloat = Defaults.spacing
    internal var lineSpacing: CGFloat = Defaults.spacing

    internal func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    internal func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var originY = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            var originX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let centeredY = originY + (row.height - size.height) / Defaults.centeringDivisor
                subviews[index].place(
                    at: CGPoint(x: originX, y: centeredY),
                    proposal: ProposedViewSize(size)
                )
                originX += size.width + spacing
            }
            originY += row.height + lineSpacing
        }
    }

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, projected > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
