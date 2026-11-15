import SwiftUI

internal struct HookSetupView: View {
    private enum Layout {
        static let width: CGFloat = 620
        static let height: CGFloat = 650
        static let headerSpacing: CGFloat = 10
        static let titleSpacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 20
        static let headerVerticalPadding: CGFloat = 14
        static let contentSpacing: CGFloat = 14
        static let contentVerticalPadding: CGFloat = 18
        static let footerVerticalPadding: CGFloat = 12
        static let topPadding: CGFloat = 4
    }

    internal let aliasStore: LaunchAliasStore
    internal let folderStore: FolderStore
    internal let onClose: () -> Void

    @State private var status = HookInstaller.Status(scriptInstalled: false, aliases: [])
    @State private var lastMessage: String?
    @State private var isError: Bool = false
    @State private var isAliasEditorPresented = false
    @State private var editingAlias: LaunchAlias?
    @State private var prefilledCommand: String?

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content }
            Divider()
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
        .onAppear { refreshStatus() }
        .onChange(of: aliasStore.customAliases) { refreshStatus() }
        .sheet(isPresented: $isAliasEditorPresented) {
            LaunchAliasEditorView(store: aliasStore, alias: editingAlias, initialCommand: prefilledCommand)
        }
    }

    /// Base commands of project launch commands that may be unregistered Claude accounts.
    private var unregisteredCommands: [String] {
        UnregisteredClaudeCommand.candidates(
            forLaunchCommands: folderStore.folders.map(\.launchCommand),
            aliases: aliasStore.aliases
        )
    }

    private var header: some View {
        HStack(spacing: Layout.headerSpacing) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text("Aliases & Claude Hooks")
                    .font(.headline)
                Text("Notify VSVibe when any Claude alias finishes or needs input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.headerVerticalPadding)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            aliasesSection
            UnregisteredCommandsSection(commands: unregisteredCommands, register: registerAccount) { command in
                editingAlias = nil
                prefilledCommand = command
                isAliasEditorPresented = true
            }
            Divider()
            hookStatusSection

            if let lastMessage {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.green)
                    .padding(.top, Layout.topPadding)
            }

            Text(
                "VSVibe writes a small bash script to `~/.vsvibe/hooks/` and adds entries under "
                    + "`hooks.SessionStart`, `hooks.Stop` and `hooks.Notification` in each Claude-family "
                    + "alias's settings.json (SessionStart lets VSVibe resume each pane's conversation "
                    + "after a relaunch). "
                    + "Existing entries are preserved; a `.vsvibe.bak` backup is written next to each file "
                    + "before mutation."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, Layout.topPadding)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.contentVerticalPadding)
    }

    @ViewBuilder private var aliasesSection: some View {
        HStack {
            Text("Custom aliases").font(.headline)
            Spacer()
            Button("Add Alias…", systemImage: "plus") {
                editingAlias = nil
                prefilledCommand = nil
                isAliasEditorPresented = true
            }
            .disabled(aliasStore.loadError != nil)
        }
        Text(
            "Register a command or alias already available in your shell. "
                + "Add its Claude config directory to enable hooks and usage tracking."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if let error = aliasStore.loadError {
            Text(error).font(.caption).foregroundStyle(.red)
        } else if aliasStore.customAliases.isEmpty {
            Text("No custom aliases yet.").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(aliasStore.customAliases) { alias in
            aliasRow(alias)
        }
    }

    @ViewBuilder private var hookStatusSection: some View {
        Text("Hook status").font(.headline)
        HookStatusRow(
            label: "Hook script",
            detail: status.scriptOutdated
                ? "Outdated — click Update Hooks: \(HookInstaller.hookScriptURL.path)"
                : HookInstaller.hookScriptURL.path,
            isOK: status.scriptInstalled && !status.scriptOutdated
        )

        ForEach(status.aliases) { aliasStatus in
            let displayPath = aliasStatus.alias.settingsURL.map { HomePath.abbreviate($0.path) } ?? "(no config)"
            HookStatusRow(
                label: "\(aliasStatus.alias.command) — \(displayPath)",
                detail: aliasStatus.summary,
                isOK: aliasStatus.isInstalled
            )
            if let hint = aliasStatus.setupHint() {
                Label(LocalizedStringKey(hint), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        ForEach(HookInstaller.unsupportedAliases(in: aliasStore.aliases)) { alias in
            HookStatusRow(
                label: "\(alias.command) — separate hook system",
                detail: "Notifications not yet supported for this CLI.",
                isOK: false,
                iconOverride: "minus.circle.fill",
                iconColor: .secondary
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
            if status.isFullyInstalled {
                Button("Uninstall", role: .destructive) {
                    runOperation("Removed hooks from all aliases.") {
                        try HookInstaller.uninstall(aliases: aliasStore.aliases)
                    }
                }
            } else {
                Button(status.installActionTitle) {
                    runOperation("Installed hooks for all aliases. Restart any running Claude session to apply.") {
                        try HookInstaller.install(aliases: aliasStore.aliases)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.footerVerticalPadding)
    }

    private func aliasRow(_ alias: LaunchAlias) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(alias.command).font(.system(.body, design: .monospaced))
                Text(alias.claudeConfigDir?.path ?? "No Claude config directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Edit") {
                editingAlias = alias
                prefilledCommand = nil
                isAliasEditorPresented = true
            }
            Button("Remove", role: .destructive) {
                runOperation("Removed alias. Existing project commands are unchanged.") {
                    try aliasStore.remove(command: alias.command)
                }
            }
        }
    }

    private func runOperation(_ successMessage: String, _ operation: () throws -> Void) {
        do {
            try operation()
            refreshStatus()
            lastMessage = successMessage
            isError = false
        } catch {
            lastMessage = "Failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func registerAccount(_ command: UnregisteredClaudeCommand) {
        guard let configDir = command.configDir else {
            return
        }
        runOperation("Registered \(command.command) and installed its hooks. Restart its running sessions to apply.") {
            try ClaudeAccountRegistrar.register(command: command.command, configDir: configDir, in: aliasStore)
        }
    }

    private func refreshStatus() {
        status = HookInstaller.currentStatus(aliases: aliasStore.aliases)
    }
}
