import SwiftUI

internal struct MainToolbar: ToolbarContent {
    @Environment(AppEnvironment.self)
    private var env

    internal var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DiskSpaceLabel(monitor: env.diskSpaceMonitor)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                env.beginCreateProjectFlow()
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .help("New Project (⇧⌘O)")
        }
    }
}
