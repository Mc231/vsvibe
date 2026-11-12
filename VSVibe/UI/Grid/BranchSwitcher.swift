import SwiftUI

/// Popover content that lists a folder's local git branches and switches to the
/// one tapped. Loads the list on appear and reports a successful switch back via
/// `onSwitched` so the pane chrome can update immediately.
struct BranchSwitcher: View {
    let folderURL: URL
    let currentBranch: String
    let onSwitched: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var branches: [String] = []
    @State private var isLoading = true
    @State private var switching: String?
    @State private var errorMessage: String?

    var body: some View {
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
                    .padding(6)
                }
                .frame(maxHeight: 300)
            }

            if let errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .frame(width: 260)
        .task { await load() }
    }

    private func branchRow(_ name: String) -> some View {
        let isCurrent = name == currentBranch
        return Button {
            Task { await switchTo(name) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "checkmark" : "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                Text(name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if switching == name {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || switching != nil)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content(); Spacer(minLength: 0) }
            .padding(12)
    }

    private func load() async {
        let url = folderURL
        let result = await Task.detached { GitInfo.localBranches(forFolder: url) }.value
        branches = result
        isLoading = false
    }

    private func switchTo(_ name: String) async {
        guard switching == nil else { return }
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
