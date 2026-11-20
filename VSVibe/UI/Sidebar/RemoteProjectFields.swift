import SwiftUI

/// The SSH fields of the project editor: host, port, remote folder, command
/// and "Runs Claude". Parsing and validation live in `RemoteProjectForm`.
internal struct RemoteProjectFields: View {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let itemSpacing: CGFloat = 6
        static let portWidth: CGFloat = 80
    }

    @Binding internal var form: RemoteProjectForm

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            hostFields
            EditorField(label: "Remote folder") {
                TextField("~/projects/app", text: $form.remotePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            EditorField(label: "Remote command") {
                commandFields
            }
            if let error = form.visibleError {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("ssh must log in without a prompt (keys or agent), or type the password in the pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hostFields: some View {
        HStack(alignment: .bottom, spacing: Layout.spacing) {
            EditorField(label: "Host") {
                TextField("user@host or ~/.ssh/config Host", text: $form.destination)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            EditorField(label: "Port") {
                TextField("22", text: $form.port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Layout.portWidth)
            }
        }
    }

    private var commandFields: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            TextField("claude (empty: just a shell)", text: $form.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Toggle("Runs Claude (resume the conversation when the pane is restored)", isOn: $form.runsClaude)
                .toggleStyle(.checkbox)
                .disabled(!form.canRunClaude)
        }
    }
}
