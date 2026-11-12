import SwiftUI

internal struct EmptyStateView: View {
    private enum Layout {
        static let spacing: CGFloat = 16
        static let iconSize: CGFloat = 56
        static let buttonSpacing: CGFloat = 10
        static let buttonHorizontalPadding: CGFloat = 12
        static let buttonVerticalPadding: CGFloat = 6
        static let padding: CGFloat = 40
    }

    @Environment(AppEnvironment.self)
    private var env

    internal var body: some View {
        VStack(spacing: Layout.spacing) {
            Image(systemName: hasShortcuts ? "play.rectangle.on.rectangle" : "square.grid.2x2")
                .font(.system(size: Layout.iconSize, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(hasShortcuts ? "No panes open" : "No shortcuts yet")
                .font(.title2)
                .fontWeight(.medium)
            Text(
                hasShortcuts
                    ? "Click a shortcut in the sidebar to open it."
                    : "Add a folder to create a shortcut."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            actionButtons
        }
        .padding(Layout.padding)
    }

    private var hasShortcuts: Bool { !env.folderStore.folders.isEmpty }

    private var actionButtons: some View {
        HStack(spacing: Layout.buttonSpacing) {
            Button {
                env.beginCreateProjectFlow()
            } label: {
                Label("New Project", systemImage: "plus")
                    .padding(.horizontal, Layout.buttonHorizontalPadding)
                    .padding(.vertical, Layout.buttonVerticalPadding)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command, .shift])
            if hasShortcuts {
                Button {
                    env.openAllShortcuts()
                } label: {
                    Label("Open All", systemImage: "play.fill")
                        .padding(.horizontal, Layout.buttonHorizontalPadding)
                        .padding(.vertical, Layout.buttonVerticalPadding)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
}
