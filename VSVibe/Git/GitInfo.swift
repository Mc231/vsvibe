import Foundation

/// Reads git branch information from disk without spawning a subprocess.
/// Walks up from a folder to the nearest `.git`, then parses its `HEAD`.
internal enum GitInfo {
    // MARK: - Branch listing / switching (subprocess)
    //
    // Reading the current branch is a cheap file read (below), but enumerating
    // and switching branches needs git's working-tree machinery, so these
    // shell out. They are only invoked on explicit user interaction, never
    // polled — run them off the main thread.

    internal enum GitError: Error, Sendable {
        case failed(String)
        case launchFailed

        internal var message: String {
            switch self {
            case .launchFailed:
                return "Couldn't run git."

            case .failed(let message):
                return message
            }
        }
    }

    private enum Constants {
        static let refPrefix = "ref:"
        static let shortSHALength = 7
        static let numstatFieldCount = 3
        /// The path is the last numstat field; splitting stops before it so
        /// tab characters inside paths survive.
        static let numstatPathIndex = 2
        static let aheadBehindFieldCount = 2
    }

    /// Default trailing window for `collectStats`, in days.
    internal static let defaultStatsWindowDays = 30

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Locates the `HEAD` file for `folderURL` by walking up to the nearest
    /// `.git`. Handles worktrees/submodules where `.git` is a file containing
    /// `gitdir: <path>` rather than a directory.
    internal static func headFileURL(forFolder folderURL: URL) -> URL? {
        let fileManager = FileManager.default
        var dir = folderURL.standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return dotGit.appendingPathComponent("HEAD")
                }
                return worktreeHeadURL(dotGitFile: dotGit, base: dir)
            }
            // Foundation can represent the parent of `/` as `/..`, then
            // `/../..`, so comparing unnormalized parent paths never terminates.
            // A non-repository project hit this loop on the main-thread poll.
            guard dir.path != "/", !dir.path.isEmpty else {
                return nil
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path {
                return nil
            }
            dir = parent
        }
    }

    /// Current branch name, or a short SHA when in detached HEAD state. Returns
    /// nil when `folderURL` is not inside a git repository.
    internal static func currentBranch(forFolder folderURL: URL) -> String? {
        guard let head = headFileURL(forFolder: folderURL) else {
            return nil
        }
        guard let raw = try? String(contentsOf: head, encoding: .utf8) else {
            return nil
        }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return nil
        }
        if line.hasPrefix(Constants.refPrefix) {
            let ref = line.dropFirst(Constants.refPrefix.count).trimmingCharacters(in: .whitespaces)
            let prefix = "refs/heads/"
            return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
        }
        // Detached HEAD: HEAD holds a raw commit SHA.
        return String(line.prefix(Constants.shortSHALength))
    }

    /// Local branch names (`refs/heads/`), in git's default ordering. Empty when
    /// not a repo or on error.
    internal static func localBranches(forFolder folderURL: URL) -> [String] {
        guard let stdout = successfulOutput(
            ["for-each-ref", "--format=%(refname:short)", "refs/heads/"],
            inFolder: folderURL
        ) else {
            return []
        }
        return stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Checks out an existing local branch. Surfaces git's stderr on failure
    /// (e.g. a dirty working tree that would be overwritten).
    internal static func switchBranch(_ branch: String, forFolder folderURL: URL) -> Result<Void, GitError> {
        guard let result = runGit(["switch", branch], inFolder: folderURL) else {
            return .failure(.launchFailed)
        }
        if result.exitCode == 0 {
            return .success(())
        }
        let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(.failed(message.isEmpty ? "git switch failed (exit \(result.exitCode))" : message))
    }

    // MARK: - Aggregate stats (subprocess, on demand)

    /// Collects commit/churn metrics over a trailing window plus current
    /// snapshot fields (branch, ahead/behind, last commit). All on-demand; not
    /// persisted.
    internal static func collectStats(
        forFolder folderURL: URL,
        windowDays: Int = defaultStatsWindowDays
    ) -> GitStats {
        var stats = GitStats(windowDays: windowDays)
        guard headFileURL(forFolder: folderURL) != nil else {
            return stats
        }
        stats.isRepo = true
        stats.currentBranch = currentBranch(forFolder: folderURL)
        stats.branchCount = localBranches(forFolder: folderURL).count

        let since = "\(windowDays) days ago"
        if let output = successfulOutput(["rev-list", "--count", "--since=\(since)", "HEAD"], inFolder: folderURL) {
            stats.commitsInWindow = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        if let output = successfulOutput(
            ["log", "--since=\(since)", "--numstat", "--format=", "HEAD"],
            inFolder: folderURL
        ) {
            applyNumstat(output, to: &stats)
        }
        if let output = successfulOutput(
            ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            inFolder: folderURL
        ) {
            applyAheadBehind(output, to: &stats)
        }
        if let output = successfulOutput(["log", "-1", "--format=%cI%n%s", "HEAD"], inFolder: folderURL) {
            applyLastCommit(output, to: &stats)
        }
        return stats
    }

    private static func worktreeHeadURL(dotGitFile: URL, base: URL) -> URL? {
        guard let contents = try? String(contentsOf: dotGitFile, encoding: .utf8) else {
            return nil
        }
        let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir:"
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let path = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        let gitDir = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        return gitDir.appendingPathComponent("HEAD")
    }

    /// Sums `git log --numstat` lines (`added<TAB>removed<TAB>path`).
    private static func applyNumstat(_ output: String, to stats: inout GitStats) {
        var added = 0
        var removed = 0
        var files = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.split(
                separator: "\t",
                maxSplits: Constants.numstatPathIndex,
                omittingEmptySubsequences: false
            )
            guard parts.count == Constants.numstatFieldCount else {
                continue
            }
            added += Int(parts[0]) ?? 0   // "-" for binary files → 0
            removed += Int(parts[1]) ?? 0
            let path = String(parts[Constants.numstatPathIndex])
            if !path.isEmpty {
                files.insert(path)
            }
        }
        stats.linesAdded = added
        stats.linesRemoved = removed
        stats.filesTouched = files.count
    }

    /// Parses `rev-list --left-right --count` output (`behind<TAB>ahead`).
    private static func applyAheadBehind(_ output: String, to stats: inout GitStats) {
        let nums = output.split { $0 == "\t" || $0 == " " || $0 == "\n" }.compactMap { Int($0) }
        guard nums.count == Constants.aheadBehindFieldCount else {
            return
        }
        stats.behind = nums[0]
        stats.ahead = nums[1]
    }

    /// Parses `log -1 --format=%cI%n%s` output (ISO date line, subject line).
    private static func applyLastCommit(_ output: String, to stats: inout GitStats) {
        let lines = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if let first = lines.first {
            stats.lastCommitDate = isoDateFormatter.date(from: String(first).trimmingCharacters(in: .whitespaces))
        }
        if lines.count > 1 {
            stats.lastCommitSubject = String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// stdout of a git command that exited 0 (and was not truncated), else nil.
    private static func successfulOutput(_ args: [String], inFolder folderURL: URL) -> String? {
        guard let result = runGit(args, inFolder: folderURL), result.exitCode == 0 else {
            return nil
        }
        return result.stdout
    }

    private static func runGit(_ args: [String], inFolder folderURL: URL) -> GitCommand.Output? {
        guard let result = try? GitCommand.run(args, in: folderURL), !result.truncated else {
            return nil
        }
        return result
    }
}
