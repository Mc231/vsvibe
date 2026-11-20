import AppKit
import SwiftUI

internal struct ProjectEditorView: View {
    private enum Layout {
        static let width: CGFloat = 480
        static let headerSpacing: CGFloat = 10
        static let titleSpacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 20
        static let headerVerticalPadding: CGFloat = 14
        static let formSpacing: CGFloat = 16
        static let formVerticalPadding: CGFloat = 18
        static let footerVerticalPadding: CGFloat = 12
        static let itemSpacing: CGFloat = 6
    }

    /// Debounce before probing the login shell, so we don't spawn one per keystroke.
    private static let loginShellProbeDelayNanoseconds: UInt64 = 400_000_000

    internal let mode: ProjectEditorMode
    /// Labels offered for assignment, in sidebar order.
    internal let availableLabels: [ProjectLabel]
    internal let availableAliases: [String]
    /// Registered aliases; unregistered Claude shell aliases are offered for registration.
    internal let aliasStore: LaunchAliasStore
    internal let onSave: (ProjectEditorResult) -> Void
    internal let onCancel: () -> Void

    @State private var draft = ProjectDraft()
    @State private var openImmediately: Bool = true
    @State private var missingCommand: String?
    @State private var selectedLabelIDs: [ProjectLabel.ID] = []
    @State private var hookSetup: RemoteHookSetupModel

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: Layout.width)
        .onAppear { populate() }
        .task(id: draft.isRemote ? "" : LaunchCommandResolver.baseCommand(of: draft.trimmedLaunchCommand)) {
            await checkCommandAvailability()
        }
    }

    private var title: String {
        mode.isCreate ? "New Project" : "Edit Project"
    }

    private var saveLabel: String {
        mode.isCreate ? "Create" : "Save"
    }

    private var header: some View {
        HStack(spacing: Layout.headerSpacing) {
            Image(systemName: draft.isRemote ? "network" : "square.stack.3d.up.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(title)
                    .font(.headline)
                Text(draft.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.headerVerticalPadding)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Layout.formSpacing) {
            Picker("Location", selection: $draft.isRemote) {
                Text("Local folder").tag(false)
                Text("Remote (SSH)").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            EditorField(label: "Name") {
                TextField(draft.isRemote ? draft.remote.suggestedName : "Project name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            if draft.isRemote {
                RemoteProjectFields(
                    form: $draft.remote,
                    hookSetup: hookSetup,
                    checksHooksAutomatically: !mode.isCreate
                )
            } else {
                localFields
            }

            EditorField(label: "Labels") {
                labelPicker
            }

            if mode.isCreate {
                Toggle("Open pane immediately after creating", isOn: $openImmediately)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.formVerticalPadding)
    }

    @ViewBuilder private var localFields: some View {
        if draft.localFolder == nil {
            EditorField(label: "Folder") {
                Button("Choose Folder…") {
                    AddFolderCommand.run { url in
                        draft.localFolder = url
                    }
                }
            }
        }
        EditorField(label: "Launch command") {
            launchCommandEditor
        }
    }

    private var launchCommandEditor: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            TextField("claude", text: $draft.launchCommand)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack(spacing: Layout.itemSpacing) {
                ForEach(availableAliases, id: \.self) { alias in
                    CommandChip(
                        text: alias,
                        isSelected: draft.trimmedLaunchCommand == alias
                    ) {
                        draft.launchCommand = alias
                    }
                }
                Spacer()
            }
            if let missing = missingCommand {
                Label(
                    "'\(missing)' doesn't seem to be installed — the pane will open a plain shell.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            ClaudeAccountNoticeView(launchCommand: draft.trimmedLaunchCommand, aliasStore: aliasStore)
        }
    }

    @ViewBuilder private var labelPicker: some View {
        if availableLabels.isEmpty {
            Text("No labels yet — create one from the sidebar's label button.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            FlowLayout(spacing: Layout.itemSpacing, lineSpacing: Layout.itemSpacing) {
                ForEach(availableLabels) { label in
                    LabelChip(label: label, isSelected: selectedLabelIDs.contains(label.id)) {
                        toggle(label.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if !draft.isRemote, let folder = draft.localFolder {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(saveLabel) {
                commit()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canSave)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.footerVerticalPadding)
    }

    internal init(
        mode: ProjectEditorMode,
        aliasStore: LaunchAliasStore,
        remoteHookInstaller: RemoteHookInstaller,
        availableLabels: [ProjectLabel] = [],
        availableAliases: [String] = LaunchCommandResolver.knownAliases,
        onSave: @escaping (ProjectEditorResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        _hookSetup = State(initialValue: RemoteHookSetupModel(installer: remoteHookInstaller))
        self.availableLabels = availableLabels
        self.availableAliases = availableAliases
        self.aliasStore = aliasStore
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// Live availability check for the entered local command. Fast PATH probe
    /// first; when that misses, confirm via the interactive login shell
    /// (off-main, debounced so we don't spawn a shell per keystroke; aliases
    /// from `~/.zshrc` count). Warning only — never blocks saving, and a shell
    /// that times out never warns. Remote commands are not checked locally.
    private func checkCommandAvailability() async {
        let base = LaunchCommandResolver.baseCommand(of: draft.trimmedLaunchCommand)
        guard !draft.isRemote, !base.isEmpty else {
            missingCommand = nil
            return
        }
        if CommandLocator.resolveExecutable(base, searchPaths: EnvBuilder.searchPaths()) != nil {
            missingCommand = nil
            return
        }
        try? await Task.sleep(nanoseconds: Self.loginShellProbeDelayNanoseconds)
        guard !Task.isCancelled else {
            return
        }
        let shell = ShellResolver.userLoginShell()
        let availability = await Task.detached(priority: .utility) {
            CommandLocator.loginShellAvailability(base, shell: shell)
        }
        .value
        guard !Task.isCancelled else {
            return
        }
        missingCommand = availability == .missing ? base : nil
    }

    private func populate() {
        switch mode {
        case .create(let url):
            draft = ProjectDraft(creatingAt: url)
            openImmediately = true
            selectedLabelIDs = []

        case .createRemote:
            draft = ProjectDraft()
            openImmediately = true
            selectedLabelIDs = []

        case .edit(let folder):
            draft = ProjectDraft(editing: folder)
            openImmediately = false
            selectedLabelIDs = folder.labelIDs
        }
    }

    private func toggle(_ id: ProjectLabel.ID) {
        if let index = selectedLabelIDs.firstIndex(of: id) {
            selectedLabelIDs.remove(at: index)
        } else {
            selectedLabelIDs.append(id)
        }
    }

    private func commit() {
        guard draft.canSave, let location = draft.location else {
            return
        }
        onSave(
            ProjectEditorResult(
                name: draft.effectiveName,
                location: location,
                openImmediately: openImmediately,
                labelIDs: selectedLabelIDs
            )
        )
    }
}
