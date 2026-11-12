import SwiftUI

struct LaunchAliasEditorView: View {
    let store: LaunchAliasStore
    let alias: LaunchAlias?
    @Environment(\.dismiss) private var dismiss
    @State private var command = ""
    @State private var configPath = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(alias == nil ? "Add Alias" : "Edit Alias").font(.headline)
            Form {
                TextField("Command", text: $command, prompt: Text("claude-work"))
                TextField("Claude config directory", text: $configPath, prompt: Text("~/.claude-work"))
            }
            Text("Use an existing shell command without arguments. The directory must match that command’s CLAUDE_CONFIG_DIR. Leave it empty for commands that do not use Claude hooks. Changes apply to newly opened panes.")
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
        .padding(20)
        .frame(width: 520)
        .onAppear {
            command = alias?.command ?? ""
            configPath = alias?.claudeConfigDir?.path ?? ""
        }
    }
}
