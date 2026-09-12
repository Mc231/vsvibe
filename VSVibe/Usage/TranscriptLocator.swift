import Foundation

/// Resolves Claude transcript locations for a project folder + launch alias.
enum TranscriptLocator {
    /// Encoded directory name Claude uses under `<config>/projects/`.
    /// Mirrors Claude's convention: replace `/` and `.` with `-`.
    static func encodedProjectName(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// Project transcript directory for a given alias config dir + folder URL.
    static func projectDir(claudeConfigDir: URL, folderURL: URL) -> URL {
        let encoded = encodedProjectName(for: folderURL)
        return claudeConfigDir
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(encoded, isDirectory: true)
    }

    /// Most recently modified `.jsonl` file in the project transcript directory,
    /// or nil if none exists.
    static func latestTranscript(in projectDir: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let jsonl = entries.filter { $0.pathExtension == "jsonl" }
        return jsonl.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }
}
