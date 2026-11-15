import Foundation

/// Which Claude transcript a pane's token usage is read from.
internal enum TranscriptSource: Equatable, Sendable {
    /// The pane's own conversation, from its hook events (`transcript_path`).
    case file(URL)
    /// The most recently modified transcript of `folderURL` under `configDir`
    /// (the launch command's alias): the best guess before the pane's first
    /// hook event.
    case latest(folderURL: URL, configDir: URL)

    /// The pane's own transcript when its path is known (an absolute `.jsonl`
    /// path), else the latest transcript under `fallbackConfigDir`, else
    /// nothing to track.
    internal static func select(transcriptPath: String?, fallbackConfigDir: URL?, folderURL: URL) -> Self? {
        if let transcriptPath, transcriptPath.hasPrefix("/"), transcriptPath.hasSuffix(".jsonl") {
            return .file(URL(fileURLWithPath: transcriptPath))
        }
        return fallbackConfigDir.map { .latest(folderURL: folderURL, configDir: $0) }
    }

    /// The transcript file to read now, or nil when it doesn't exist (yet).
    internal func currentTranscript(fileManager: FileManager = .default) -> URL? {
        switch self {
        case .file(let url):
            return fileManager.fileExists(atPath: url.path) ? url : nil

        case let .latest(folderURL, configDir):
            let projectDir = TranscriptLocator.projectDir(claudeConfigDir: configDir, folderURL: folderURL)
            return TranscriptLocator.latestTranscript(in: projectDir)
        }
    }
}
