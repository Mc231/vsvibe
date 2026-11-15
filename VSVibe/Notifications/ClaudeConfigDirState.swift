import Foundation

/// Whether a Claude alias's config dir has been used by Claude Code yet. A
/// registered alias whose dir is missing or untouched has never been run (or
/// never logged in), so the hook setup tells the user to run it once.
internal enum ClaudeConfigDirState: Equatable {
    /// The directory does not exist.
    case missing
    /// The directory holds nothing but what VSVibe writes itself
    /// (`settings.json` and its `.vsvibe.bak` backup): Claude never ran here.
    case notSetUp
    /// Claude Code has written to the directory.
    case ready

    /// Files `HookInstaller` creates; their presence alone doesn't mean Claude ran.
    private static let vsvibeFiles: Set<String> = ["settings.json", "settings.json.vsvibe.bak", ".DS_Store"]

    internal static func of(_ directory: URL, fileManager: FileManager = .default) -> Self {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.contains { !vsvibeFiles.contains($0) } ? .ready : .notSetUp
    }
}
