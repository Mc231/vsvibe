import SwiftUI

/// Under the project editor's launch command: when the command is a shell
/// alias for a Claude account VSVibe doesn't know (`CLAUDE_CONFIG_DIR=…`),
/// offers to register it and install its hooks.
internal struct ClaudeAccountNoticeView: View {
    private enum Layout {
        static let spacing: CGFloat = 6
    }

    /// Debounce before asking the shell, so typing doesn't spawn one per keystroke.
    private static let probeDelayNanoseconds: UInt64 = 400_000_000

    internal let launchCommand: String
    internal let aliasStore: LaunchAliasStore

    @State private var detected: UnregisteredClaudeCommand?
    @State private var message: String?
    @State private var isError = false

    private var candidate: String? {
        UnregisteredClaudeCommand.candidate(forLaunchCommand: launchCommand, aliases: aliasStore.aliases)
    }

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            if let detected, let notice = detected.notice() {
                HStack(spacing: Layout.spacing) {
                    Label(LocalizedStringKey(notice), systemImage: "person.crop.circle.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Register") { register(detected) }
                        .controlSize(.small)
                }
            }
            if let message {
                Text(LocalizedStringKey(message))
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
        }
        .task(id: candidate) { await detect() }
    }

    private func detect() async {
        detected = nil
        guard let candidate else {
            return
        }
        try? await Task.sleep(nanoseconds: Self.probeDelayNanoseconds)
        guard !Task.isCancelled else {
            return
        }
        let result = await UnregisteredClaudeCommand.detect(candidate)
        guard !Task.isCancelled, result.configDir != nil else {
            return
        }
        detected = result
    }

    private func register(_ command: UnregisteredClaudeCommand) {
        guard let configDir = command.configDir else {
            return
        }
        do {
            try ClaudeAccountRegistrar.register(command: command.command, configDir: configDir, in: aliasStore)
            detected = nil
            message = "Registered `\(command.command)` and installed its hooks. Restart its running sessions to apply."
            isError = false
        } catch {
            message = "Couldn't register `\(command.command)`: \(error.localizedDescription)"
            isError = true
        }
    }
}
