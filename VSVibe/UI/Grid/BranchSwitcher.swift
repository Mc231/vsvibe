import SwiftUI

/// Popover content that lists a folder's local git branches and switches to the
/// one tapped. Loads the list on appear and reports a successful switch back via
/// `onSwitched` so the pane chrome can update immediately.
internal struct BranchSwitcher: View {
    private enum Layout {
        static let listPadding: CGFloat = 6
        static let listMaxHeight: CGFloat = 300
        static let errorFontSize: CGFloat = 11
        static let errorPadding: CGFloat = 8
        static let width: CGFloat = 260
        static let rowSpacing: CGFloat = 6
        static let iconSize: CGFloat = 10
        static let iconWidth: CGFloat = 14
        static let nameFontSize: CGFloat = 12
        static let spacerMinLength: CGFloat = 4
        static let rowVerticalPadding: CGFloat = 4
        static let rowHorizontalPadding: CGFloat = 6
        static let placeholderPadding: CGFloat = 12
    }

    internal let folderURL: URL
    internal let currentBranch: String
    internal let onSwitched: (String) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State private var branches: [String] = []
    @State private var isLoading = true
    @State private var switching: String?
    @State private var errorMessage: String?

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                row { ProgressView().controlSize(.small) }
            } else if branches.isEmpty {
                row { Text("No branches").foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(branches, id: \.self) { name in
                            branchRow(name)
                        }
                    }
                    .padding(Layout.listPadding)
                }
                .frame(maxHeight: Layout.listMaxHeight)
            }

            if let errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.system(size: Layout.errorFontSize))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(Layout.errorPadding)
            }
        }
        .frame(width: Layout.width)
        .task { await load() }
    }

    private func branchRow(_ name: String) -> some View {
        let isCurrent = name == currentBranch
        return Button {
            Task { await switchTo(name) }
        } label: {
            HStack(spacing: Layout.rowSpacing) {
                Image(systemName: isCurrent ? "checkmark" : "arrow.triangle.branch")
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .frame(width: Layout.iconWidth)
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    .accessibilityLabel(isCurrent ? "Current branch" : "Branch")
                Text(name)
                    .font(.system(size: Layout.nameFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Layout.spacerMinLength)
                if switching == name {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, Layout.rowVerticalPadding)
            .padding(.horizontal, Layout.rowHorizontalPadding)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || switching != nil)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content()
            Spacer(minLength: 0)
        }
        .padding(Layout.placeholderPadding)
    }

    private func load() async {
        let url = folderURL
        let result = await Task.detached { GitInfo.localBranches(forFolder: url) }.value
        branches = result
        isLoading = false
    }

    private func switchTo(_ name: String) async {
        guard switching == nil else {
            return
        }
        switching = name
        errorMessage = nil
        let url = folderURL
        let result = await Task.detached { GitInfo.switchBranch(name, forFolder: url) }.value
        switching = nil
        switch result {
        case .success:
            onSwitched(name)
            dismiss()

        case .failure(let error):
            errorMessage = error.message
        }
    }
}
