import SwiftUI
import AppKit

struct HookSetupView: View {
    let onClose: () -> Void

    @State private var status: HookInstaller.Status = HookInstaller.currentStatus()
    @State private var lastMessage: String?
    @State private var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body_
            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Hooks")
                    .font(.headline)
                Text("Notify VSVibe when any Claude alias finishes or needs input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBlock(
                label: "Hook script",
                detail: HookInstaller.hookScriptURL.path,
                ok: status.scriptInstalled
            )

            ForEach(status.aliases) { aliasStatus in
                let path = aliasStatus.alias.settingsURL?.path ?? "(no config)"
                statusBlock(
                    label: "\(aliasStatus.alias.command) — \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))",
                    detail: aliasStatus.isInstalled
                        ? "Stop + Notification registered"
                        : aliasStatus.registeredEvents.isEmpty
                            ? "Not registered"
                            : "Partial: \(aliasStatus.registeredEvents.joined(separator: ", "))",
                    ok: aliasStatus.isInstalled
                )
            }

            ForEach(HookInstaller.unsupportedAliases()) { alias in
                statusBlock(
                    label: "\(alias.command) — separate hook system",
                    detail: "Notifications not yet supported for this CLI.",
                    ok: false,
                    iconOverride: "minus.circle.fill",
                    iconColor: .secondary
                )
            }

            if let lastMessage {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.green)
                    .padding(.top, 4)
            }

            Text("VSVibe writes a small bash script to `~/.vsvibe/hooks/` and adds entries under `hooks.Stop` and `hooks.Notification` in each Claude-family alias's settings.json. Existing entries are preserved; a `.vsvibe.bak` backup is written next to each file before mutation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
            if status.isFullyInstalled {
                Button("Uninstall", role: .destructive) {
                    runOperation("Removed hooks from all aliases.") { try HookInstaller.uninstall() }
                }
            } else {
                Button(status.isPartiallyInstalled ? "Reinstall Hooks" : "Install Hooks") {
                    runOperation("Installed hooks for all aliases. Restart any running Claude session to apply.") {
                        try HookInstaller.install()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusBlock(label: String,
                             detail: String,
                             ok: Bool,
                             iconOverride: String? = nil,
                             iconColor: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconOverride ?? (ok ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(iconColor ?? (ok ? Color.green : Color.secondary))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private func runOperation(_ successMessage: String, _ op: () throws -> Void) {
        do {
            try op()
            status = HookInstaller.currentStatus()
            lastMessage = successMessage
            isError = false
        } catch {
            lastMessage = "Failed: \(error.localizedDescription)"
            isError = true
        }
    }
}
