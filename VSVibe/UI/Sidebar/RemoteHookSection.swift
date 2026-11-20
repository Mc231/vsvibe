import SwiftUI

/// The project editor's "Claude hooks on host" section for a remote project:
/// the hook state on the host and a button to install or update them. Logic
/// lives in `RemoteHookSetupModel` / `RemoteHookInstaller`.
internal struct RemoteHookSection: View {
    private enum Layout {
        static let spacing: CGFloat = 6
    }

    /// Delay before the automatic check, so editing the host doesn't run ssh per keystroke.
    private static let autoCheckDelayNanoseconds: UInt64 = 800_000_000

    /// The valid target being edited; nil while the fields are invalid.
    internal let target: RemoteTarget?
    /// Check the hooks when the target appears or changes (editing an existing project).
    internal let checksAutomatically: Bool
    internal let model: RemoteHookSetupModel

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            if let target {
                HStack(spacing: Layout.spacing) {
                    Button(model.actionTitle(host: target.host)) {
                        Task { await model.install(target) }
                    }
                    Button("Check") {
                        Task { await model.check(target) }
                    }
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .disabled(model.isBusy)
                if !model.statusText.isEmpty {
                    Label(model.statusText, systemImage: model.isInstalled ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(model.isInstalled ? Color.green : Color.secondary)
                }
            } else {
                Text("Enter a valid host to set up the Claude hooks there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Remote notifications and token usage need the hooks on the host (bash; python3 recommended).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: target) {
            model.reset()
            guard checksAutomatically, let target else {
                return
            }
            try? await Task.sleep(nanoseconds: Self.autoCheckDelayNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            await model.check(target)
        }
    }
}
