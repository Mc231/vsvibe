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
        static let statusIconSize: CGFloat = 16
        static let statusLabelSize: CGFloat = 12
        static let statusDetailSize: CGFloat = 11
        static let statusDetailLineLimit = 2
    }

    internal let aliasStore: LaunchAliasStore
    internal let onClose: () -> Void

    @State private var status = HookInstaller.Status(scriptInstalled: false, aliases: [])
    @State private var lastMessage: String?
    @State private var isError: Bool = false
    @State private var isAliasEditorPresented = false
    @State private var editingAlias: LaunchAlias?

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
            LaunchAliasEditorView(store: aliasStore, alias: editingAlias)
        }
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
        statusBlock(
            label: "Hook script",
            detail: status.scriptOutdated
                ? "Outdated — click Update Hooks: \(HookInstaller.hookScriptURL.path)"
                : HookInstaller.hookScriptURL.path,
            isOK: status.scriptInstalled && !status.scriptOutdated
        )

        ForEach(status.aliases) { aliasStatus in
            let path = aliasStatus.alias.settingsURL?.path ?? "(no config)"
            let displayPath = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            statusBlock(
                label: "\(aliasStatus.alias.command) — \(displayPath)",
                detail: aliasStatus.isInstalled
                    ? "SessionStart + Stop + Notification registered"
                    : aliasStatus.registeredEvents.isEmpty
                        ? "Not registered"
                        : "Partial: \(aliasStatus.registeredEvents.joined(separator: ", "))",
                isOK: aliasStatus.isInstalled
            )
        }

        ForEach(HookInstaller.unsupportedAliases(in: aliasStore.aliases)) { alias in
            statusBlock(
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
                isAliasEditorPresented = true
            }
            Button("Remove", role: .destructive) {
                runOperation("Removed alias. Existing project commands are unchanged.") {
                    try aliasStore.remove(command: alias.command)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBlock(
        label: String,
        detail: String,
        isOK: Bool,
        iconOverride: String? = nil,
        iconColor: Color? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: Layout.headerSpacing) {
            Image(systemName: iconOverride ?? (isOK ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(iconColor ?? (isOK ? Color.green : Color.secondary))
                .font(.system(size: Layout.statusIconSize))
                .accessibilityLabel(isOK ? "Installed" : "Not installed")
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(label).font(.system(size: Layout.statusLabelSize, weight: .semibold))
                Text(detail)
                    .font(.system(size: Layout.statusDetailSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(Layout.statusDetailLineLimit)
                    .truncationMode(.middle)
            }
            Spacer()
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

    private func refreshStatus() {
        status = HookInstaller.currentStatus(aliases: aliasStore.aliases)
    }
}
