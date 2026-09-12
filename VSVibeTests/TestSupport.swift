import Foundation
import XCTest

/// Filesystem + git helpers for tests. Each call to `makeTempDir` creates a
/// unique directory; callers are responsible for cleanup (most tests track them
/// and remove in tearDown).
enum TestSupport {
    static func makeTempDir(_ name: String = "vsvibe-test") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    static func git(_ args: [String], in dir: URL) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        // Deterministic identity + no signing so commits work in CI/sandbox.
        var env = ProcessInfo.processInfo.environment
        env["GIT_AUTHOR_NAME"] = "Test"
        env["GIT_AUTHOR_EMAIL"] = "test@test.test"
        env["GIT_COMMITTER_NAME"] = "Test"
        env["GIT_COMMITTER_EMAIL"] = "test@test.test"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_SYSTEM"] = "/dev/null"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "launch failed: \(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Creates an initialized repo with one commit on the default branch and
    /// returns its directory.
    static func makeRepo(initialBranch: String = "main") -> URL {
        let dir = makeTempDir("repo")
        git(["init", "-b", initialBranch], in: dir)
        write("hello\n", to: dir.appendingPathComponent("README.md"))
        git(["add", "."], in: dir)
        git(["commit", "-m", "init"], in: dir)
        return dir
    }

    static func write(_ contents: String, to url: URL) {
        try? contents.data(using: .utf8)!.write(to: url)
    }

    /// Encodes a JSONL transcript line (object → single line + newline).
    static func jsonl(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
