import SwiftUI

internal struct LaunchAliasEditorView: View {
    private enum Layout {
        static let spacing: CGFloat = 16
        static let padding: CGFloat = 20
        static let width: CGFloat = 520
    }

    internal let store: LaunchAliasStore
    internal let alias: LaunchAlias?
    /// Command to prefill when adding (e.g. an unregistered project command).
    internal var initialCommand: String?
    @Environment(\.dismiss)
    private var dismiss
    @State private var command = ""
    @State private var configPath = ""
    @State private var errorMessage: String?

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(alias == nil ? "Add Alias" : "Edit Alias").font(.headline)
            Form {
                TextField("Command", text: $command, prompt: Text("claude-work"))
                TextField("Claude config directory", text: $configPath, prompt: Text("~/.claude-work"))
            }
            Text(
                "Use an existing shell command without arguments. "
                    + "The directory must match that command’s CLAUDE_CONFIG_DIR. "
                    + "Leave it empty for commands that do not use Claude hooks. "
                    + "Changes apply to newly opened panes."
            )
            .font(.caption).foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try store.save(command: command, configPath: configPath, replacing: alias?.command)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .onAppear {
            command = alias?.command ?? initialCommand ?? ""
            configPath = alias?.claudeConfigDir?.path ?? ""
        }
    }
}
