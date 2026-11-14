import SwiftUI

/// Settings › Updates: Sparkle's automatic check / download preferences.
internal struct UpdatesSettingsTab: View {
    private enum Layout {
        static let width: CGFloat = 420
    }

    internal let model: UpdateViewModel

    internal var body: some View {
        Form {
            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { model.automaticallyChecksForUpdates },
                    set: { model.setAutomaticallyChecksForUpdates($0) }
                )
            )
            Toggle(
                "Automatically download and install updates",
                isOn: Binding(
                    get: { model.automaticallyDownloadsUpdates },
                    set: { model.setAutomaticallyDownloadsUpdates($0) }
                )
            )
            .disabled(!model.automaticallyChecksForUpdates)
            LabeledContent("Current version") {
                Text(model.versionDescription).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Check Now") { model.checkForUpdates() }
                    .disabled(!model.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
