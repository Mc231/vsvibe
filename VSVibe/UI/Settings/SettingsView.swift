import SwiftUI

/// The app's Settings window (⌘,): one tab per settings area, each in its own file.
internal struct SettingsView: View {
    private enum Layout {
        static let width: CGFloat = 480
    }

    internal let updates: UpdateViewModel

    internal var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            UpdatesSettingsTab(model: updates)
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
        }
        .frame(width: Layout.width)
    }
}
