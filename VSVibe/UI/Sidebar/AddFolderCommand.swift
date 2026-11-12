import AppKit
import Foundation

@MainActor
internal enum AddFolderCommand {
    private static var activePanel: NSOpenPanel?

    internal static func run(completion: @escaping (URL) -> Void) {
        guard activePanel == nil else {
            return
        }
        let panel = NSOpenPanel()
        activePanel = panel
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Choose a folder"
        panel.prompt = "Add"
        panel.message = "Pick a folder, then choose the project name and launch command."

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let url = response == .OK ? panel.url : nil
            activePanel = nil
            DispatchQueue.main.async {
                guard let url else {
                    return
                }
                completion(url)
            }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
