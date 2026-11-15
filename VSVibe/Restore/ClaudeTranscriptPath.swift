import Foundation

/// Where a Claude Code conversation lives on disk: the hook payload's
/// `transcript_path`, `<config dir>/projects/<project slug>/<session id>.jsonl`.
/// Restore uses it to tell which Claude config dir, and so which launch alias,
/// owns a conversation.
internal enum ClaudeTranscriptPath {
    private static let projectsDirectoryName = "projects"
    private static let transcriptExtension = "jsonl"

    /// `path` when it is the transcript of `claudeSessionID`: an absolute path
    /// without control characters whose file name is `<claudeSessionID>.jsonl`.
    /// Nil otherwise (including a nil `path`).
    internal static func validated(_ path: String?, claudeSessionID: String) -> String? {
        guard let path,
            path.hasPrefix("/"),
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            path.hasSuffix("/\(claudeSessionID).\(transcriptExtension)")
        else {
            return nil
        }
        return path
    }

    /// The Claude config dir owning the transcript at `path`: the nearest
    /// ancestor that contains the `projects` directory on the path. Nil when
    /// no ancestor directory is named `projects`.
    internal static func configDir(ofTranscript path: String) -> URL? {
        let directories = URL(fileURLWithPath: path).standardizedFileURL.pathComponents.dropLast()
        guard let projectsIndex = directories.lastIndex(of: projectsDirectoryName) else {
            return nil
        }
        // pathComponents of an absolute URL start with "/".
        let configPath = "/" + directories[..<projectsIndex].dropFirst().joined(separator: "/")
        return URL(fileURLWithPath: configPath, isDirectory: true)
    }

    /// `path` in a form that compares equal for the same directory: a leading
    /// `~` expanded, `.`/`..` removed and symlinks resolved.
    internal static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: LaunchAliasStore.expandingTilde(in: path))
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
