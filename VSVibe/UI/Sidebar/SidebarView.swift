import SwiftUI

internal struct SidebarView: View {
    private enum Layout {
        static let doubleTapCount = 2
        static let emptyHintPadding: CGFloat = 2
        static let footerSpacing: CGFloat = 6
        static let footerButtonSize: CGFloat = 22
        static let footerDividerHeight: CGFloat = 14
        static let footerHorizontalPadding: CGFloat = 8
        static let footerVerticalPadding: CGFloat = 6
    }

    @Environment(AppEnvironment.self)
    private var env
    @State private var selection: SidebarRowID?

    internal var body: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                section(for: group)
            }
        }
        .listStyle(.sidebar)
        .onKeyPress(.return) {
            if let folder = selectedFolder {
                env.openOrFocus(folder: folder)
                return .handled
            }
            return .ignored
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .sheet(item: Binding(get: { env.pendingEditor }, set: { env.pendingEditor = $0 })) { mode in
            ProjectEditorView(
                mode: mode,
                availableLabels: env.folderStore.labels,
                availableAliases: env.aliasStore.aliases.map(\.command),
                onSave: { result in env.commitEditor(mode: mode, result: result) },
                onCancel: { env.cancelEditor() }
            )
        }
        .sheet(item: Binding(get: { env.pendingLabelEditor }, set: { env.pendingLabelEditor = $0 })) { mode in
            LabelEditorView(
                mode: mode,
                usedColors: env.folderStore.labels.map(\.colorHex),
                onSave: { result in env.commitLabelEditor(mode: mode, result: result) },
                onCancel: { env.cancelLabelEditor() }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { env.isManageLabelsPresented },
                set: { env.isManageLabelsPresented = $0 }
            )
        ) {
            ManageLabelsView { env.isManageLabelsPresented = false }
        }
    }

    private var groups: [SidebarGroup] { env.folderStore.sidebarGroups }

    /// The project behind the current selection, if it still exists.
    private var selectedFolder: FolderEntry? {
        guard let selection else {
            return nil
        }
        return env.folderStore.folders.first { $0.id == selection.folderID }
    }

    private var sidebarFooter: some View {
        HStack(spacing: Layout.footerSpacing) {
            footerButton(systemImage: "plus", label: "New Project") {
                env.beginCreateProjectFlow()
            }
            .help("New Project (⇧⌘O)")

            footerButton(systemImage: "minus", label: "Remove Folder") {
                if let folder = selectedFolder {
                    env.removeFolderPermanently(id: folder.id)
                    selection = nil
                }
            }
            .disabled(selectedFolder == nil)
            .help("Remove Folder")

            Divider()
                .frame(height: Layout.footerDividerHeight)

            footerButton(systemImage: "folder.badge.gearshape", label: "Manage Labels") {
                env.presentManageLabels()
            }
            .help("Manage Labels")

            Spacer()
        }
        .padding(.horizontal, Layout.footerHorizontalPadding)
        .padding(.vertical, Layout.footerVerticalPadding)
        .background(.bar)
    }

    private func section(for group: SidebarGroup) -> some View {
        Section(isExpanded: expandedBinding(for: group)) {
            ForEach(group.folders) { folder in
                row(for: folder, in: group)
            }
            .onMove { source, dest in
                env.folderStore.move(
                    inGroupWithFolderIDs: group.folders.map(\.id),
                    fromOffsets: source,
                    toOffset: dest
                )
            }
            if group.folders.isEmpty, group.label != nil {
                Text("No projects — assign this label from a project's context menu.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, Layout.emptyHintPadding)
            }
        } header: {
            SectionHeader(group: group)
                .contextMenu { groupContextMenu(group) }
        }
    }

    private func row(for folder: FolderEntry, in group: SidebarGroup) -> some View {
        SidebarRow(
            folder: folder,
            labels: env.folderStore.labels(for: folder),
            currentLabelID: group.label?.id,
            isActive: env.sessionManager.hasSession(forFolder: folder.id),
            onOpenOrFocus: { env.openOrFocus(folder: folder) },
            onContinue: { env.continueOrFocus(folder: folder) }
        )
        .tag(SidebarRowID(groupID: group.id, folderID: folder.id))
        .contentShape(Rectangle())
        .onTapGesture(count: Layout.doubleTapCount) {
            env.openOrFocus(folder: folder)
        }
        .contextMenu {
            folderContextMenu(folder)
        }
    }

    private func footerButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: Layout.footerButtonSize, height: Layout.footerButtonSize)
                .accessibilityLabel(label)
        }
        .buttonStyle(.borderless)
    }

    private func expandedBinding(for group: SidebarGroup) -> Binding<Bool> {
        Binding(
            get: { !group.isCollapsed },
            set: { expanded in
                if let label = group.label {
                    env.folderStore.setLabelCollapsed(id: label.id, !expanded)
                } else {
                    env.folderStore.setUngroupedCollapsed(!expanded)
                }
            }
        )
    }

    @ViewBuilder
    private func groupContextMenu(_ group: SidebarGroup) -> some View {
        if let label = group.label {
            Button("Open All Panes") { env.openAllPanes(inLabel: label.id) }
                .disabled(group.folders.isEmpty)
            Button("Close All Panes") { env.closeAllPanes(inLabel: label.id) }
                .disabled(group.folders.isEmpty)
            Divider()
            Button("Edit Label…") { env.beginEditLabelFlow(label) }
            Button("Delete Label", role: .destructive) {
                env.folderStore.deleteLabel(id: label.id)
            }
            Divider()
        }
        Button("New Label…") { env.beginCreateLabelFlow() }
        Button("Manage Labels…") { env.presentManageLabels() }
    }

    @ViewBuilder
    private func folderContextMenu(_ folder: FolderEntry) -> some View {
        let activePanes = env.sessionManager.sessions(forFolder: folder.id)
        if let first = activePanes.first {
            Button(activePanes.count > 1 ? "Focus First Pane" : "Focus Pane") {
                env.sessionManager.focus(id: first.id)
            }
            Button(activePanes.count > 1 ? "Close All Panes" : "Close Pane") {
                env.sessionManager.closeAllSessions(forFolder: folder.id)
            }
            Button(activePanes.count > 1 ? "Restart First Pane" : "Restart Pane") {
                env.sessionManager.reload(id: first.id)
            }
        } else {
            Button("Open Pane") {
                env.reopenPane(for: folder)
            }
            Button("Continue Last Session") {
                env.continueOrFocus(folder: folder)
            }
        }
        Divider()
        labelsMenu(folder)
        Menu("Open In") {
            ForEach(EditorRegistry.availableEditors()) { editor in
                Button {
                    EditorRegistry.open(folder: folder.url, with: editor)
                } label: {
                    Label(editor.displayName, systemImage: editor.iconSystemName)
                }
            }
            if EditorRegistry.availableEditors().isEmpty {
                Text("No supported editors detected")
            }
        }
        Button("Project Stats…") {
            env.showStats(folder: folder)
        }
        Button("Review Git Changes…") {
            env.pendingGitReview = folder
        }
        Button("Edit Project…") {
            env.beginEditProjectFlow(folder: folder)
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
        }
        Divider()
        Button("Remove Project", role: .destructive) {
            env.removeFolderPermanently(id: folder.id)
        }
    }

    /// Multi-select label assignment: a project can carry several labels and
    /// then shows up under each of their sections.
    @ViewBuilder
    private func labelsMenu(_ folder: FolderEntry) -> some View {
        Menu("Labels") {
            ForEach(env.folderStore.labels) { label in
                let isOn = folder.labelIDs.contains(label.id)
                Button {
                    env.folderStore.toggleLabel(label.id, for: folder.id)
                } label: {
                    Label(isOn ? "✓ \(label.name)" : label.name, systemImage: label.symbolName)
                }
            }
            if !env.folderStore.labels.isEmpty {
                Divider()
                Button("Clear Labels") {
                    env.folderStore.setLabels([], for: folder.id)
                }
                .disabled(folder.labelIDs.isEmpty)
            }
            Button("New Label…") {
                env.beginCreateLabelFlow(assignTo: folder.id)
            }
        }
    }
}
