import SwiftUI

/// The Settings window (⌘,): one tab per file in this folder.
internal struct SettingsView: View {
    internal let updates: UpdateViewModel

    internal var body: some View {
        TabView {
            UpdatesSettingsTab(model: updates)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .scenePadding()
    }
}
