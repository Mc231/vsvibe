import SwiftUI
import AppKit

enum ProjectEditorMode: Identifiable, Equatable {
    case create(url: URL)
    case edit(folder: FolderEntry)

    var id: String {
        switch self {
        case .create(let url): "create:\(url.path)"
        case .edit(let folder): "edit:\(folder.id.uuidString)"
        }
    }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}

struct ProjectEditorView: View {
    let mode: ProjectEditorMode
    /// Labels offered for assignment, in sidebar order.
    let availableLabels: [ProjectLabel]
    let availableAliases: [String]
    let onSave: (ProjectEditorResult) -> Void
    let onCancel: () -> Void

    init(mode: ProjectEditorMode,
         availableLabels: [ProjectLabel] = [],
         availableAliases: [String] = LaunchCommandResolver.knownAliases,
         onSave: @escaping (ProjectEditorResult) -> Void,
         onCancel: @escaping () -> Void) {
        self.mode = mode
        self.availableLabels = availableLabels
        self.availableAliases = availableAliases
        self.onSave = onSave
        self.onCancel = onCancel
    }

    @State private var name: String = ""
    @State private var launchCommand: String = ""
    @State private var openImmediately: Bool = true
    @State private var missingCommand: String?
    @State private var selectedLabelIDs: [ProjectLabel.ID] = []

    private var url: URL {
        switch mode {
        case .create(let url): url
        case .edit(let folder): folder.url
        }
    }

    private var title: String {
        mode.isCreate ? "New Project" : "Edit Project"
    }

    private var saveLabel: String {
        mode.isCreate ? "Create" : "Save"
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCommand: String { launchCommand.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !trimmedCommand.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 480)
        .onAppear { populate() }
        .task(id: LaunchCommandResolver.baseCommand(of: trimmedCommand)) {
            await checkCommandAvailability()
        }
    }

    /// Live availability check for the entered command. Fast PATH probe first;
    /// when that misses, confirm via the login shell (off-main, debounced so we
    /// don't spawn a shell per keystroke). Warning only — never blocks saving.
    private func checkCommandAvailability() async {
        let base = LaunchCommandResolver.baseCommand(of: trimmedCommand)
        guard !base.isEmpty else {
            missingCommand = nil
            return
        }
        if CommandLocator.resolveExecutable(base, searchPaths: EnvBuilder.searchPaths()) != nil {
            missingCommand = nil
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        let shell = ShellResolver.userLoginShell()
        let found = await Task.detached(priority: .utility) {
            CommandLocator.loginShellCanFind(base, shell: shell)
        }.value
        guard !Task.isCancelled else { return }
        missingCommand = found ? nil : base
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(label: "Name") {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field(label: "Launch command") {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("claude", text: $launchCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack(spacing: 6) {
                        ForEach(availableAliases, id: \.self) { alias in
                            CommandChip(
                                text: alias,
                                isSelected: trimmedCommand == alias
                            ) {
                                launchCommand = alias
                            }
                        }
                        Spacer()
                    }
                    if let missing = missingCommand {
                        Label("'\(missing)' doesn't seem to be installed — the pane will open a plain shell.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            field(label: "Labels") {
                if availableLabels.isEmpty {
                    Text("No labels yet — create one from the sidebar's label button.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(availableLabels) { label in
                            LabelChip(label: label, isSelected: selectedLabelIDs.contains(label.id)) {
                                toggle(label.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if mode.isCreate {
                Toggle("Open pane immediately after creating", isOn: $openImmediately)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(saveLabel) {
                commit()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func populate() {
        switch mode {
        case .create(let url):
            name = url.lastPathComponent
            launchCommand = LaunchCommandResolver.defaultCommand(for: url)
            openImmediately = true
            selectedLabelIDs = []
        case .edit(let folder):
            name = folder.displayName
            launchCommand = folder.launchCommand
            openImmediately = false
            selectedLabelIDs = folder.labelIDs
        }
    }

    private func toggle(_ id: ProjectLabel.ID) {
        if let idx = selectedLabelIDs.firstIndex(of: id) {
            selectedLabelIDs.remove(at: idx)
        } else {
            selectedLabelIDs.append(id)
        }
    }

    private func commit() {
        guard canSave else { return }
        onSave(ProjectEditorResult(
            name: trimmedName,
            launchCommand: trimmedCommand,
            openImmediately: openImmediately,
            labelIDs: selectedLabelIDs
        ))
    }
}

struct ProjectEditorResult {
    let name: String
    let launchCommand: String
    let openImmediately: Bool
    let labelIDs: [ProjectLabel.ID]

    init(name: String,
         launchCommand: String,
         openImmediately: Bool,
         labelIDs: [ProjectLabel.ID] = []) {
        self.name = name
        self.launchCommand = launchCommand
        self.openImmediately = openImmediately
        self.labelIDs = labelIDs
    }
}

private struct LabelChip: View {
    let label: ProjectLabel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: label.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text(label.name)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(label.color.opacity(isSelected ? 0.22 : 0.10)))
            .foregroundStyle(isSelected ? label.color : Color.secondary)
            .overlay(
                Capsule().strokeBorder(isSelected ? label.color.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CommandChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
