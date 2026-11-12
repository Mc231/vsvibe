import SwiftUI

/// Right-hand pane of the git review sheet: the selected file's path and its diff.
internal struct GitReviewPatchPane: View {
    private enum Layout {
        static let pathPadding: CGFloat = 12
        static let minWidth: CGFloat = 450
    }

    internal let selectedPath: String?
    internal let isLoading: Bool
    internal let errorMessage: String?
    internal let patch: String

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedPath {
                Text(selectedPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(Layout.pathPadding)
                Divider()
            }
            if isLoading {
                ProgressView("Loading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to load diff",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if selectedPath != nil {
                DiffTextView(text: patch)
            } else {
                ContentUnavailableView("Select a file", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: Layout.minWidth, maxWidth: .infinity, maxHeight: .infinity)
    }
}
