import Foundation

internal enum AppPaths {
    internal static let appName = "VSVibe"

    internal static var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        let found = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appDirectory(in: baseDirectory(found: found, home: NSHomeDirectory()), fileManager: fileManager)
    }

    internal static var stateFile: URL {
        applicationSupportDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    internal static var statsFile: URL {
        applicationSupportDirectory.appendingPathComponent("stats.json", isDirectory: false)
    }

    internal static var aliasesFile: URL {
        applicationSupportDirectory.appendingPathComponent("aliases.json", isDirectory: false)
    }

    /// The Application Support base: the system-reported directory, or
    /// `~/Library/Application Support` when the system reports none.
    internal static func baseDirectory(found: URL?, home: String) -> URL {
        found ?? URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support")
    }

    /// `<base>/VSVibe`, created on first access.
    internal static func appDirectory(in base: URL, fileManager: FileManager = .default) -> URL {
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
