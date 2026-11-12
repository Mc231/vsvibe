import SwiftUI

internal struct GitReviewView: View {
    /// Identity of one comparison load; `refresh` forces a reload of the
    /// same branches (used as the `.task(id:)` key).
    private struct Request: Equatable {
        let base: String
        let target: String
        let mode: GitComparisonMode
        let refresh: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.base == rhs.base && lhs.target == rhs.target && lhs.mode == rhs.mode && lhs.refresh == rhs.refresh
        }
    }

    private enum Layout {
        static let titleSpacing: CGFloat = 4
        static let outerPadding: CGFloat = 20
        static let pickerSpacing: CGFloat = 16
        static let rangePickerWidth: CGFloat = 255
        static let sectionBottomPadding: CGFloat = 12
        static let footerPadding: CGFloat = 12
        static let minWidth: CGFloat = 900
        static let idealWidth: CGFloat = 1_100
        static let minHeight: CGFloat = 580
        static let idealHeight: CGFloat = 740
        static let rowVerticalPadding: CGFloat = 3
        static let listMinWidth: CGFloat = 200
        static let listIdealWidth: CGFloat = 280
        static let listMaxWidth: CGFloat = 400
    }

    internal let folder: FolderEntry
    @Environment(\.dismiss)
    private var dismiss
    @State private var branches: [GitReviewBranch] = []
    @State private var base = ""
    @State private var target = ""
    @State private var mode = GitComparisonMode.mergeBase
    @State private var comparison: GitComparison?
    @State private var selectedPath: String?
    @State private var patch = ""
    @State private var error: String?
    @State private var patchError: String?
    @State private var loadingBranches = true
    @State private var comparing = false
    @State private var loadingPatch = false
    @State private var refresh = 0

    internal var body: some View {
        VStack(spacing: 0) {
            header
            pickers
            rangeDescription
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(
            minWidth: Layout.minWidth,
            idealWidth: Layout.idealWidth,
            minHeight: Layout.minHeight,
            idealHeight: Layout.idealHeight
        )
        .task(id: refresh) { await loadBranches() }
        .task(id: request) { await compare() }
        .task(id: patchID) { await loadPatch() }
    }

    private var request: Request { Request(base: base, target: target, mode: mode, refresh: refresh) }
    private var patchID: [String] {
        [comparison?.baseCommit ?? "", comparison?.targetCommit ?? "", selectedPath ?? ""]
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text("Git Changes").font(.title2.bold())
                Text(folder.displayName).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                refresh += 1
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(loadingBranches || comparing)
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(Layout.outerPadding)
    }

    private var pickers: some View {
        HStack(spacing: Layout.pickerSpacing) {
            Picker("Base", selection: $base) {
                if branches.isEmpty { Text("No branches").tag("") }
                ForEach(branches) { Text($0.name).tag($0.id) }
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker("Compare", selection: $target) {
                if branches.isEmpty { Text("No branches").tag("") }
                ForEach(branches) { Text($0.name).tag($0.id) }
            }
            Picker("Range", selection: $mode) {
                ForEach(GitComparisonMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: Layout.rangePickerWidth)
        }
        .disabled(loadingBranches || branches.isEmpty)
        .padding(.horizontal, Layout.outerPadding)
        .padding(.bottom, Layout.sectionBottomPadding)
    }

    private var rangeDescription: some View {
        Text(
            mode == .mergeBase
                ? "Committed changes on Compare since its common ancestor with Base. Local edits are excluded."
                : "Committed differences from Base to Compare. Local edits are excluded."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.outerPadding)
        .padding(.bottom, Layout.sectionBottomPadding)
    }

    private var footer: some View {
        HStack {
            if let comparison {
                Text("\(comparison.files.count) changed files")
                Text("+\(comparison.files.compactMap(\.added).reduce(0, +))").foregroundStyle(.green)
                Text("−\(comparison.files.compactMap(\.removed).reduce(0, +))").foregroundStyle(.red)
            }
            Spacer()
            Text("Read-only comparison • Local and cached remote branches")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(Layout.footerPadding)
    }

    @ViewBuilder private var content: some View {
        if loadingBranches || comparing {
            ProgressView(loadingBranches ? "Loading branches…" : "Comparing branches…")
        } else if let error {
            ContentUnavailableView(
                "Unable to compare",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if let comparison, comparison.files.isEmpty {
            ContentUnavailableView(
                "No changes",
                systemImage: "checkmark.circle",
                description: Text("The selected branches have no differences in this range.")
            )
        } else if let comparison {
            HSplitView {
                fileList(comparison)
                GitReviewPatchPane(
                    selectedPath: selectedPath,
                    isLoading: loadingPatch,
                    errorMessage: patchError,
                    patch: patch
                )
            }
        }
    }

    private func fileList(_ comparison: GitComparison) -> some View {
        List(comparison.files, selection: $selectedPath) { file in
            GitReviewFileRow(file: file)
                .padding(.vertical, Layout.rowVerticalPadding)
                .tag(file.path)
        }
        .frame(minWidth: Layout.listMinWidth, idealWidth: Layout.listIdealWidth, maxWidth: Layout.listMaxWidth)
    }

    private func loadBranches() async {
        loadingBranches = true
        error = nil
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { (try GitReview.branches(in: url), GitInfo.currentBranch(forFolder: url)) }
        }
        .value
        guard !Task.isCancelled else {
            return
        }
        loadingBranches = false
        switch result {
        case .success(let (items, current)):
            branches = items
            if !items.contains(where: { $0.id == target }) {
                let currentRef = "refs/heads/" + (current ?? "")
                target = items.first { $0.id == currentRef }?.id ?? "HEAD"
            }
            if !items.contains(where: { $0.id == base }) {
                base = items.first { $0.id == "refs/heads/main" && $0.id != target }?.id
                    ?? items.first { $0.id == "refs/heads/master" && $0.id != target }?.id
                    ?? items.first { $0.id != target && $0.id != "HEAD" }?.id ?? target
            }

        case .failure(let failure):
            branches = []
            comparison = nil
            error = message(failure)
        }
    }

    private func compare() async {
        guard !base.isEmpty, !target.isEmpty else {
            return
        }
        comparing = true
        error = nil
        comparison = nil
        selectedPath = nil
        let request = request
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try GitReview.compare(in: url, base: request.base, target: request.target, mode: request.mode)
            }
        }
        .value
        guard !Task.isCancelled else {
            return
        }
        comparing = false
        switch result {
        case .success(let value):
            comparison = value
            selectedPath = value.files.first?.path

        case .failure(let failure):
            error = message(failure)
        }
    }

    private func loadPatch() async {
        patch = ""
        patchError = nil
        loadingPatch = false
        guard let comparison, let file = comparison.files.first(where: { $0.path == selectedPath }) else {
            return
        }
        loadingPatch = true
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { try GitReview.patch(in: url, comparison: comparison, file: file) }
        }
        .value
        guard !Task.isCancelled else {
            return
        }
        loadingPatch = false
        switch result {
        case .success(let text):
            patch = text

        case .failure(let failure):
            patchError = message(failure)
        }
    }

    private func message(_ error: Error) -> String {
        (error as? GitInfo.GitError)?.message ?? error.localizedDescription
    }
}
