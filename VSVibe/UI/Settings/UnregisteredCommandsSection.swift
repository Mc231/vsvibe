import SwiftUI

/// Hook setup section listing project launch commands that aren't registered
/// aliases, with the Claude account each one's shell alias uses (when found)
/// and a one-click Register.
internal struct UnregisteredCommandsSection: View {
    private enum Layout {
        static let detailSize: CGFloat = 11
    }

    internal let commands: [String]
    /// Registers a command whose config dir was detected.
    internal let register: (UnregisteredClaudeCommand) -> Void
    /// Opens the alias editor for a command without a detected config dir.
    internal let addManually: (String) -> Void

    @State private var detected: [String: UnregisteredClaudeCommand] = [:]

    internal var body: some View {
        if !commands.isEmpty {
            Text("Unregistered launch commands").font(.headline)
            Text(
                "Projects run these commands, but VSVibe doesn't know which Claude account they use, "
                    + "so their panes get no hooks, usage tracking or restore. VSVibe reads "
                    + "CLAUDE_CONFIG_DIR from the alias in your shell."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(commands, id: \.self) { command in
                row(command)
            }
            .task(id: commands) { await detectAll() }
        }
    }

    private func row(_ command: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(command).font(.system(.body, design: .monospaced))
                Text(detail(for: command))
                    .font(.system(size: Layout.detailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let found = detected[command], found.configDir != nil {
                Button("Register") { register(found) }
            } else {
                Button("Register…") { addManually(command) }
                    .disabled(detected[command] == nil)
            }
        }
    }

    private func detail(for command: String) -> String {
        guard let found = detected[command] else {
            return "Checking your shell…"
        }
        guard let path = found.displayConfigDir() else {
            return "No CLAUDE_CONFIG_DIR found in its shell definition"
        }
        return "Claude account \(path)"
    }

    private func detectAll() async {
        for command in commands where detected[command] == nil {
            let found = await UnregisteredClaudeCommand.detect(command)
            guard !Task.isCancelled else {
                return
            }
            detected[command] = found
        }
    }
}
