import SwiftUI

/// A compact menu button that lists every installed editor and opens
/// `folder` in the chosen one.
internal struct OpenInMenu: View {
    private enum Layout {
        static let compactIconSize: CGFloat = 10
    }

    internal let folder: URL
    internal var compact: Bool = true

    internal var body: some View {
        Menu {
            ForEach(EditorRegistry.availableEditors()) { editor in
                Button {
                    EditorRegistry.open(folder: folder, with: editor)
                } label: {
                    Label(editor.displayName, systemImage: editor.iconSystemName)
                }
            }
            if EditorRegistry.availableEditors().isEmpty {
                Text("No supported editors detected")
                    .foregroundStyle(.secondary)
            }
        } label: {
            if compact {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: Layout.compactIconSize, weight: .semibold))
                    .accessibilityLabel("Open In")
            } else {
                Label("Open In", systemImage: "arrow.up.forward.app")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Open Folder In…")
    }
}
