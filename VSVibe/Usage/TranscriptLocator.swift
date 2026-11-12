import Foundation

/// Resolves Claude transcript locations for a project folder + launch alias.
internal enum TranscriptLocator {
    /// Encoded directory name Claude uses under `<config>/projects/`.
    /// Mirrors Claude's convention: replace `/` and `.` with `-`.
    internal static func encodedProjectName(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Project transcript directory for a given alias config dir + folder URL.
    internal static func projectDir(claudeConfigDir: URL, folderURL: URL) -> URL {
        let encoded = encodedProjectName(for: folderURL)
        return claudeConfigDir
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(encoded, isDirectory: true)
    }

    /// Most recently modified `.jsonl` file in the project transcript directory,
    /// or nil if none exists.
    internal static func latestTranscript(in projectDir: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let jsonl = entries.filter { $0.pathExtension == "jsonl" }
        return jsonl.max { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        }
    }

    private static func modificationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }
}
