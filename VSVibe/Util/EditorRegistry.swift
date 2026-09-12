import AppKit
import Foundation
import SwiftUI

struct ExternalEditor: Identifiable, Hashable {
    let id: String
    let displayName: String
    let bundleIdentifiers: [String]
    let iconSystemName: String
    let shortcutKey: String?
    let shortcutModifiers: EventModifiers

    static func == (lhs: ExternalEditor, rhs: ExternalEditor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func resolvedAppURL() -> URL? {
        let ws = NSWorkspace.shared
        for bid in bundleIdentifiers {
            if let url = ws.urlForApplication(withBundleIdentifier: bid) {
                return url
            }
        }
        return nil
    }

    var isInstalled: Bool { resolvedAppURL() != nil }
}

@MainActor
enum EditorRegistry {
    static let all: [ExternalEditor] = [
        ExternalEditor(id: "xcode",
                       displayName: "Xcode",
                       bundleIdentifiers: ["com.apple.dt.Xcode"],
                       iconSystemName: "hammer.fill",
                       shortcutKey: "x",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "android-studio",
                       displayName: "Android Studio",
                       bundleIdentifiers: ["com.google.android.studio",
                                           "com.google.android.studio.canary"],
                       iconSystemName: "ant.fill",
                       shortcutKey: "a",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "webstorm",
                       displayName: "WebStorm",
                       bundleIdentifiers: ["com.jetbrains.WebStorm"],
                       iconSystemName: "globe",
                       shortcutKey: "w",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "intellij",
                       displayName: "IntelliJ IDEA",
                       bundleIdentifiers: ["com.jetbrains.intellij",
                                           "com.jetbrains.intellij.ce"],
                       iconSystemName: "i.square.fill",
                       shortcutKey: "i",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "pycharm",
                       displayName: "PyCharm",
                       bundleIdentifiers: ["com.jetbrains.pycharm",
                                           "com.jetbrains.pycharm.ce"],
                       iconSystemName: "p.square.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "rubymine",
                       displayName: "RubyMine",
                       bundleIdentifiers: ["com.jetbrains.rubymine"],
                       iconSystemName: "r.square.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "goland",
                       displayName: "GoLand",
                       bundleIdentifiers: ["com.jetbrains.goland"],
                       iconSystemName: "g.square.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "rider",
                       displayName: "Rider",
                       bundleIdentifiers: ["com.jetbrains.rider"],
                       iconSystemName: "r.circle.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "fleet",
                       displayName: "JetBrains Fleet",
                       bundleIdentifiers: ["com.jetbrains.fleet"],
                       iconSystemName: "bolt.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "vscode",
                       displayName: "VS Code",
                       bundleIdentifiers: ["com.microsoft.VSCode",
                                           "com.microsoft.VSCodeInsiders"],
                       iconSystemName: "chevron.left.forwardslash.chevron.right",
                       shortcutKey: "v",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "cursor",
                       displayName: "Cursor",
                       bundleIdentifiers: ["com.todesktop.230313mzl4w4u92",
                                           "com.anysphere.cursor"],
                       iconSystemName: "rays",
                       shortcutKey: "c",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "zed",
                       displayName: "Zed",
                       bundleIdentifiers: ["dev.zed.Zed",
                                           "dev.zed.Zed-Preview"],
                       iconSystemName: "z.square.fill",
                       shortcutKey: "z",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "sublime",
                       displayName: "Sublime Text",
                       bundleIdentifiers: ["com.sublimetext.4",
                                           "com.sublimetext.3"],
                       iconSystemName: "s.square.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "nova",
                       displayName: "Nova",
                       bundleIdentifiers: ["com.panic.Nova"],
                       iconSystemName: "n.square.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "finder",
                       displayName: "Finder",
                       bundleIdentifiers: ["com.apple.finder"],
                       iconSystemName: "folder.fill",
                       shortcutKey: "f",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "terminal",
                       displayName: "Terminal",
                       bundleIdentifiers: ["com.apple.Terminal"],
                       iconSystemName: "terminal.fill",
                       shortcutKey: "t",
                       shortcutModifiers: [.command, .option]),
        ExternalEditor(id: "iterm",
                       displayName: "iTerm",
                       bundleIdentifiers: ["com.googlecode.iterm2"],
                       iconSystemName: "rectangle.dashed",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "warp",
                       displayName: "Warp",
                       bundleIdentifiers: ["dev.warp.Warp-Stable",
                                           "dev.warp.Warp"],
                       iconSystemName: "bolt.horizontal.fill",
                       shortcutKey: nil,
                       shortcutModifiers: []),
        ExternalEditor(id: "ghostty",
                       displayName: "Ghostty",
                       bundleIdentifiers: ["com.mitchellh.ghostty"],
                       iconSystemName: "rectangle.split.2x1.fill",
                       shortcutKey: nil,
                       shortcutModifiers: [])
    ]

    /// Editors detected as installed on this machine.
    static func availableEditors() -> [ExternalEditor] {
        all.filter(\.isInstalled)
    }

    static func open(folder: URL, with editor: ExternalEditor) {
        guard let appURL = editor.resolvedAppURL() else {
            Log.app.error("Editor \(editor.displayName, privacy: .public) not installed")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder],
                                withApplicationAt: appURL,
                                configuration: config) { _, error in
            if let error {
                Log.app.error("Open in \(editor.displayName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
