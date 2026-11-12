import Foundation

enum AppPaths {
    static let appName = "VSVibe"

    static var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var stateFile: URL {
        applicationSupportDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    static var statsFile: URL {
        applicationSupportDirectory.appendingPathComponent("stats.json", isDirectory: false)
    }

    static var aliasesFile: URL {
        applicationSupportDirectory.appendingPathComponent("aliases.json", isDirectory: false)
    }
}
