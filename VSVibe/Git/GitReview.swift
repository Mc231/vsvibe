import Foundation

struct GitReviewBranch: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct GitChangedFile: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    let status: String
    let added: Int?
    let removed: Int?
    var isBinary: Bool { added == nil || removed == nil }
}

struct GitComparison: Sendable {
    let baseCommit: String
    let targetCommit: String
    let files: [GitChangedFile]
}

enum GitComparisonMode: String, CaseIterable, Identifiable, Sendable {
    case mergeBase = "Since common ancestor"
    case tips = "Branch tips"
    var id: Self { self }
}

/// All operations are read-only, user-triggered and run off the main actor.
enum GitReview {
    static func branches(in folder: URL) throws -> [GitReviewBranch] {
        _ = try output(["rev-parse", "--git-dir"], in: folder)
        let raw = try output(["for-each-ref", "--format=%(refname)%09%(symref)",
                              "refs/heads/", "refs/remotes/"], in: folder)
        let branches = raw.split(separator: "\n").compactMap { line -> GitReviewBranch? in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].isEmpty else { return nil }
            let ref = String(parts[0])
            let name = ref.hasPrefix("refs/heads/")
                ? String(ref.dropFirst("refs/heads/".count))
                : "remote: " + String(ref.dropFirst("refs/remotes/".count))
            return GitReviewBranch(id: ref, name: name)
        }
        guard !branches.isEmpty else {
            throw GitInfo.GitError.failed("This repository has no committed branches yet.")
        }
        return branches + [GitReviewBranch(id: "HEAD", name: "HEAD (current checkout)")]
    }

    static func compare(in folder: URL, base: String, target: String,
                        mode: GitComparisonMode) throws -> GitComparison {
        let folder = try repositoryRoot(in: folder)
        // Resolve once: file list and patches refer to the same immutable commits,
        // even if a branch moves while the review is open.
        let baseTip = try commit(base, in: folder)
        let targetTip = try commit(target, in: folder)
        let start = mode == .mergeBase
            ? try output(["merge-base", baseTip, targetTip], in: folder).trimmingCharacters(in: .whitespacesAndNewlines)
            : baseTip
        let options = ["diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--ignore-submodules=none"]
        let names = try output(options + ["--name-status", "-z", start, targetTip, "--"], in: folder)
        let counts = try output(options + ["--numstat", "-z", start, targetTip, "--"], in: folder)
        return GitComparison(baseCommit: start, targetCommit: targetTip,
                             files: parseFiles(names: names, counts: counts))
    }

    static func patch(in folder: URL, comparison: GitComparison, file: GitChangedFile) throws -> String {
        let folder = try repositoryRoot(in: folder)
        let result = try GitCommand.run(["--literal-pathspecs", "diff", "--no-ext-diff", "--no-textconv",
                                         "--no-color", "--no-renames", "--ignore-submodules=none", "--unified=3",
                                         comparison.baseCommit, comparison.targetCommit, "--", file.path],
                                        in: folder, outputLimit: 512 * 1_024)
        try check(result)
        return result.stdout + (result.truncated ? "\n… Diff preview truncated at 512 KB.\n" : "")
    }

    static func parseFiles(names: String, counts: String) -> [GitChangedFile] {
        var stats: [String: (Int?, Int?)] = [:]
        for record in counts.split(separator: "\0") {
            let columns = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            stats[String(columns[2])] = (Int(columns[0]), Int(columns[1]))
        }
        let tokens = names.split(separator: "\0")
        return stride(from: 0, to: max(0, tokens.count - 1), by: 2).map { index in
            let path = String(tokens[index + 1])
            let count = stats[path] ?? (nil, nil)
            return GitChangedFile(path: path, status: String(tokens[index]), added: count.0, removed: count.1)
        }
    }

    private static func commit(_ ref: String, in folder: URL) throws -> String {
        try output(["rev-parse", "--verify", "--end-of-options", ref + "^{commit}"], in: folder)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func repositoryRoot(in folder: URL) throws -> URL {
        let path = try output(["rev-parse", "--show-toplevel"], in: folder)
        // Remove only Git's trailing newline; spaces/newlines may belong to a path.
        return URL(fileURLWithPath: path.hasSuffix("\n") ? String(path.dropLast()) : path)
    }

    private static func output(_ arguments: [String], in folder: URL) throws -> String {
        let result = try GitCommand.run(arguments, in: folder)
        try check(result)
        guard !result.truncated else {
            throw GitInfo.GitError.failed("This comparison is too large to display. Select a narrower range.")
        }
        return result.stdout
    }

    private static func check(_ result: GitCommand.Output) throws {
        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitInfo.GitError.failed(message.isEmpty ? "Git comparison failed (exit \(result.exitCode))." : message)
        }
    }
}
