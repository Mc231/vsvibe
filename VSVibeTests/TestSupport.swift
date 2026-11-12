import Foundation
import XCTest

/// Filesystem + git helpers for tests. Each call to `makeTempDir` creates a
/// unique directory; callers are responsible for cleanup (most tests track them
/// and remove in tearDown).
internal enum TestSupport {
    /// Initial value for URL properties that `setUp` replaces. It points below
    /// `/dev/null`, so it can never exist and removing it is a no-op.
    internal static let placeholderURL = URL(fileURLWithPath: "/dev/null/vsvibe-unset", isDirectory: true)

    internal static func makeTempDir(_ name: String = "vsvibe-test") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    internal static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    internal static func git(_ args: [String], in dir: URL) -> (code: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path] + args
        // Deterministic identity + no signing so commits work in CI/sandbox.
        var env = ProcessInfo.processInfo.environment
        env["GIT_AUTHOR_NAME"] = "Test"
        env["GIT_AUTHOR_EMAIL"] = "test@test.test"
        env["GIT_COMMITTER_NAME"] = "Test"
        env["GIT_COMMITTER_EMAIL"] = "test@test.test"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_SYSTEM"] = "/dev/null"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "launch failed: \(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    /// Creates an initialized repo with one commit on the default branch and
    /// returns its directory.
    internal static func makeRepo(initialBranch: String = "main") -> URL {
        let dir = makeTempDir("repo")
        git(["init", "-b", initialBranch], in: dir)
        write("hello\n", to: dir.appendingPathComponent("README.md"))
        git(["add", "."], in: dir)
        git(["commit", "-m", "init"], in: dir)
        return dir
    }

    internal static func write(_ contents: String, to url: URL) {
        try? Data(contents.utf8).write(to: url)
    }

    /// Encodes a JSONL transcript line (object → single line + newline).
    internal static func jsonl(_ object: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            return (String(bytes: data, encoding: .utf8) ?? "") + "\n"
        } catch {
            XCTFail("Could not encode JSONL line: \(error)")
            return ""
        }
    }
}
