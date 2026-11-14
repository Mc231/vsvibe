import SwiftUI

/// The app's Settings window (⌘,): one tab per settings area, each in its own file.
internal struct SettingsView: View {
    private enum Layout {
        static let width: CGFloat = 480
    }

    internal var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: Layout.width)
    }
}
