import AppKit
import Foundation

@MainActor
enum AddFolderCommand {
    static func run(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Choose a folder"
        panel.prompt = "Add"
        panel.message = "Pick a folder. A new terminal pane will open here and run `claude`."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }
}
