import SwiftUI

/// A compact menu button that lists every installed editor and opens
/// `folder` in the chosen one.
struct OpenInMenu: View {
    let folder: URL
    var compact: Bool = true

    var body: some View {
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
                    .font(.system(size: 10, weight: .semibold))
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
