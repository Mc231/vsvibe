import SwiftUI

/// One changed file in the git review file list: status letter, path and line counts.
internal struct GitReviewFileRow: View {
    private enum Layout {
        static let spacing: CGFloat = 8
        static let statusWidth: CGFloat = 18
        static let textSpacing: CGFloat = 4
        static let pathFontSize: CGFloat = 12
        static let pathLineLimit = 2
    }

    internal let file: GitChangedFile

    internal var body: some View {
        HStack(alignment: .top, spacing: Layout.spacing) {
            Text(file.status)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(file.status == "D" ? Color.red : Color.accentColor)
                .frame(width: Layout.statusWidth)
            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                Text(file.path)
                    .font(.system(size: Layout.pathFontSize))
                    .lineLimit(Layout.pathLineLimit)
                    .truncationMode(.middle)
                if file.isBinary {
                    Text("Binary").foregroundStyle(.secondary)
                } else {
                    Text("+\(file.added ?? 0)  −\(file.removed ?? 0)").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
