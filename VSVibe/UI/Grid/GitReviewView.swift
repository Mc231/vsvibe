import SwiftUI
import AppKit

struct GitReviewView: View {
    let folder: FolderEntry
    @Environment(\.dismiss) private var dismiss
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

    private struct Request: Equatable {
        let base: String
        let target: String
        let mode: GitComparisonMode
        let refresh: Int
    }

    private var request: Request { Request(base: base, target: target, mode: mode, refresh: refresh) }
    private var patchID: [String] {
        [comparison?.baseCommit ?? "", comparison?.targetCommit ?? "", selectedPath ?? ""]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Git Changes").font(.title2.bold())
                    Text(folder.displayName).foregroundStyle(.secondary)
                }
                Spacer()
                Button { refresh += 1 } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(loadingBranches || comparing)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            HStack(spacing: 16) {
                Picker("Base", selection: $base) {
                    if branches.isEmpty { Text("No branches").tag("") }
                    ForEach(branches) { Text($0.name).tag($0.id) }
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("Compare", selection: $target) {
                    if branches.isEmpty { Text("No branches").tag("") }
                    ForEach(branches) { Text($0.name).tag($0.id) }
                }
                Picker("Range", selection: $mode) {
                    ForEach(GitComparisonMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 255)
            }
            .disabled(loadingBranches || branches.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            Text(mode == .mergeBase
                 ? "Committed changes on Compare since its common ancestor with Base. Local edits are excluded."
                 : "Committed differences from Base to Compare. Local edits are excluded.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
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
            .font(.caption).padding(12)
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 580, idealHeight: 740)
        .task(id: refresh) { await loadBranches() }
        .task(id: request) { await compare() }
        .task(id: patchID) { await loadPatch() }
    }

    @ViewBuilder private var content: some View {
        if loadingBranches || comparing {
            ProgressView(loadingBranches ? "Loading branches…" : "Comparing branches…")
        } else if let error {
            ContentUnavailableView("Unable to compare", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if let comparison, comparison.files.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                   description: Text("The selected branches have no differences in this range."))
        } else if let comparison {
            HSplitView {
                List(comparison.files, selection: $selectedPath) { file in
                    HStack(alignment: .top, spacing: 8) {
                        Text(file.status).font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(file.status == "D" ? Color.red : Color.accentColor)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.path).font(.system(size: 12)).lineLimit(2).truncationMode(.middle)
                            if file.isBinary {
                                Text("Binary").foregroundStyle(.secondary)
                            } else {
                                Text("+\(file.added ?? 0)  −\(file.removed ?? 0)").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 3).tag(file.path)
                }
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                VStack(alignment: .leading, spacing: 0) {
                    if let selectedPath {
                        Text(selectedPath).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).padding(12)
                        Divider()
                    }
                    if loadingPatch {
                        ProgressView("Loading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let patchError {
                        ContentUnavailableView("Unable to load diff", systemImage: "exclamationmark.triangle",
                                               description: Text(patchError))
                    } else if selectedPath != nil {
                        DiffTextView(text: patch)
                    } else {
                        ContentUnavailableView("Select a file", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadBranches() async {
        loadingBranches = true
        error = nil
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { (try GitReview.branches(in: url), GitInfo.currentBranch(forFolder: url)) }
        }.value
        guard !Task.isCancelled else { return }
        loadingBranches = false
        switch result {
        case .success(let (items, current)):
            branches = items
            if !items.contains(where: { $0.id == target }) {
                let currentRef = "refs/heads/" + (current ?? "")
                target = items.first(where: { $0.id == currentRef })?.id ?? "HEAD"
            }
            if !items.contains(where: { $0.id == base }) {
                base = items.first(where: { $0.id == "refs/heads/main" && $0.id != target })?.id
                    ?? items.first(where: { $0.id == "refs/heads/master" && $0.id != target })?.id
                    ?? items.first(where: { $0.id != target && $0.id != "HEAD" })?.id ?? target
            }
        case .failure(let failure):
            branches = []
            comparison = nil
            error = message(failure)
        }
    }

    private func compare() async {
        guard !base.isEmpty, !target.isEmpty else { return }
        comparing = true
        error = nil
        comparison = nil
        selectedPath = nil
        let request = request
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { try GitReview.compare(in: url, base: request.base, target: request.target, mode: request.mode) }
        }.value
        guard !Task.isCancelled else { return }
        comparing = false
        switch result {
        case .success(let value):
            comparison = value
            selectedPath = value.files.first?.path
        case .failure(let failure): error = message(failure)
        }
    }

    private func loadPatch() async {
        patch = ""
        patchError = nil
        loadingPatch = false
        guard let comparison, let file = comparison.files.first(where: { $0.path == selectedPath }) else { return }
        loadingPatch = true
        let url = folder.url
        let result = await Task.detached(priority: .userInitiated) {
            Result { try GitReview.patch(in: url, comparison: comparison, file: file) }
        }.value
        guard !Task.isCancelled else { return }
        loadingPatch = false
        switch result {
        case .success(let text): patch = text
        case .failure(let failure): patchError = message(failure)
        }
    }

    private func message(_ error: Error) -> String {
        (error as? GitInfo.GitError)?.message ?? error.localizedDescription
    }
}

/// Native text scrolling avoids creating thousands of SwiftUI diff-line views.
private struct DiffTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 12, height: 12)
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let color: NSColor? = line.hasPrefix("+") ? .systemGreen
                : line.hasPrefix("-") ? .systemRed
                : line.hasPrefix("@@") ? .systemBlue : nil
            if let color {
                attributed.addAttribute(.foregroundColor, value: color, range: NSRange(location: offset, length: length))
            }
            offset += length + 1
        }
        view.textStorage?.setAttributedString(attributed)
        // Reset both axes after AppKit lays out the new document. Scrolling the
        // selection into view can otherwise clip the start of long diff lines.
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else { return }
            scroll.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
