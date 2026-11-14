import SwiftUI

/// General settings: restoring panes on launch.
internal struct GeneralSettingsTab: View {
    @AppStorage(SessionRestoreSettings.key)
    private var restoreSessions = SessionRestoreSettings.defaultValue

    internal var body: some View {
        Form {
            Section {
                Toggle("Restore sessions on launch", isOn: $restoreSessions)
                Text(
                    "Reopens the panes that were open when VSVibe last quit, crashed or relaunched "
                        + "for an update. Panes running Claude resume their own conversation "
                        + "(needs up-to-date Claude hooks); other panes start their launch command again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
