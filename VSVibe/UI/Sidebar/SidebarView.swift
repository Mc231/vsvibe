import SwiftUI

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: SidebarRowID?

    private var groups: [SidebarGroup] { env.folderStore.sidebarGroups }

    /// The project behind the current selection, if it still exists.
    private var selectedFolder: FolderEntry? {
        guard let selection else { return nil }
        return env.folderStore.folders.first { $0.id == selection.folderID }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groups) { group in
                Section(isExpanded: expandedBinding(for: group)) {
                    ForEach(group.folders) { folder in
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
                        .onTapGesture(count: 2) {
                            env.openOrFocus(folder: folder)
                        }
                        .contextMenu {
                            folderContextMenu(folder)
                        }
                    }
                    .onMove { source, dest in
                        env.folderStore.move(inGroupWithFolderIDs: group.folders.map(\.id),
                                             fromOffsets: source,
                                             toOffset: dest)
                    }
                    if group.folders.isEmpty, group.label != nil {
                        Text("No projects — assign this label from a project's context menu.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 2)
                    }
                } header: {
                    SectionHeader(group: group)
                        .contextMenu { groupContextMenu(group) }
                }
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
        .sheet(isPresented: Binding(get: { env.isManageLabelsPresented },
                                    set: { env.isManageLabelsPresented = $0 })) {
            ManageLabelsView { env.isManageLabelsPresented = false }
        }
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

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Button {
                env.beginCreateProjectFlow()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("New Project (⇧⌘O)")

            Button {
                if let folder = selectedFolder {
                    env.removeFolderPermanently(id: folder.id)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selectedFolder == nil)
            .help("Remove Folder")

            Divider()
                .frame(height: 14)

            Button {
                env.presentManageLabels()
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Manage Labels")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
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

private struct SectionHeader: View {
    let group: SidebarGroup

    var body: some View {
        HStack(spacing: 6) {
            if let label = group.label {
                Image(systemName: label.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(label.color)
            }
            Text(group.title)
            if !group.folders.isEmpty {
                Text("\(group.folders.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SidebarRow: View {
    let folder: FolderEntry
    /// Every label on this project, used to hint at cross-section membership.
    let labels: [ProjectLabel]
    /// The section this row is rendered in (nil for the unlabelled bucket).
    let currentLabelID: ProjectLabel.ID?
    let isActive: Bool
    let onOpenOrFocus: () -> Void
    let onContinue: () -> Void

    @State private var isHovering = false

    /// Labels other than the section we're in — the project also appears there.
    private var otherLabels: [ProjectLabel] {
        labels.filter { $0.id != currentLabelID }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(folder.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if folder.launchCommand != LaunchCommandResolver.defaultCommand {
                        Text(folder.launchCommand)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    if !otherLabels.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(otherLabels) { label in
                                Circle()
                                    .fill(label.color)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .help("Also in " + otherLabels.map(\.name).joined(separator: ", "))
                    }
                }
                Text(folder.url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            if !isActive {
                Button {
                    onContinue()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .opacity(isHovering ? 1.0 : 0.55)
                .help("Continue Last Session (\(LaunchCommandResolver.continueCommand(for: folder.launchCommand)))")
            }
            Button {
                onOpenOrFocus()
            } label: {
                Image(systemName: isActive ? "arrow.up.right.square" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isActive ? 1.0 : 0.55)
            .help(isActive ? "Focus Pane" : "Open Pane")
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
