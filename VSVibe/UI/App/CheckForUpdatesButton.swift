import SwiftUI

/// App menu › "Check for Updates…" (after "About VSVibe").
internal struct CheckForUpdatesButton: View {
    internal let model: UpdateViewModel

    internal var body: some View {
        Button("Check for Updates…") { model.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}
