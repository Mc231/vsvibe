@testable import VSVibe
import XCTest

/// Transcript path validation, config-dir derivation, and matching a config
/// dir to its alias (tilde, `..` and symlinks normalised).
@MainActor
internal final class ClaudeTranscriptPathTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override internal func setUp() {
        super.setUp()
        directory = TestSupport.makeTempDir("transcript-path")
    }

    override internal func tearDown() {
        TestSupport.remove(directory)
        super.tearDown()
    }

    // MARK: - validated

    internal func testAcceptsAnAbsolutePathNamedAfterTheSession() {
        let path = "/Users/u/.claude-work/projects/-a-b/abc-1.jsonl"
        XCTAssertEqual(ClaudeTranscriptPath.validated(path, claudeSessionID: "abc-1"), path)
    }

    internal func testRejectsOtherPaths() {
        let rejected: [String?] = [
            nil,
            "",
            "relative/projects/p/abc-1.jsonl",
            "~/.claude/projects/p/abc-1.jsonl",
            "/c/projects/p/abc-2.jsonl",
            "/c/projects/p/abc-1.json",
            "/c/projects/p/abc-1.jsonl/",
            "/c/projects/p\t/abc-1.jsonl"
        ]
        for path in rejected {
            XCTAssertNil(ClaudeTranscriptPath.validated(path, claudeSessionID: "abc-1"), path ?? "nil")
        }
    }

    // MARK: - configDir

    internal func testConfigDirIsTheNearestAncestorHoldingProjects() {
        XCTAssertEqual(
            ClaudeTranscriptPath.configDir(ofTranscript: "/Users/u/.claude-work/projects/-p/s.jsonl")?.path,
            "/Users/u/.claude-work"
        )
        XCTAssertEqual(
            ClaudeTranscriptPath.configDir(ofTranscript: "/Users/u/projects/.claude/projects/-p/s.jsonl")?.path,
            "/Users/u/projects/.claude"
        )
        XCTAssertEqual(
            ClaudeTranscriptPath.configDir(ofTranscript: "/Users/u/.claude/x/../projects/-p/s.jsonl")?.path,
            "/Users/u/.claude"
        )
        XCTAssertEqual(ClaudeTranscriptPath.configDir(ofTranscript: "/projects/-p/s.jsonl")?.path, "/")
    }

    internal func testConfigDirIsNilWithoutAProjectsDirectory() {
        XCTAssertNil(ClaudeTranscriptPath.configDir(ofTranscript: "/tmp/s.jsonl"))
        XCTAssertNil(ClaudeTranscriptPath.configDir(ofTranscript: "/tmp/p/projects"))
    }

    // MARK: - canonical / alias(forConfigDir:)

    internal func testCanonicalExpandsTildeAndRemovesDots() {
        let home = ClaudeTranscriptPath.canonical(NSHomeDirectory() + "/.claude")
        XCTAssertEqual(ClaudeTranscriptPath.canonical("~/.claude"), home)
        XCTAssertEqual(ClaudeTranscriptPath.canonical("~/x/../.claude/"), home)
    }

    internal func testDefaultClaudeAliasOwnsTheHomeConfigDir() {
        let store = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude", isDirectory: true)
        XCTAssertEqual(store.alias(forConfigDir: home)?.command, "claude")
        XCTAssertNil(store.alias(forConfigDir: directory))
    }

    internal func testCustomAliasMatchesThroughSymlinks() throws {
        let real = directory.appendingPathComponent("real-config", isDirectory: true)
        let link = directory.appendingPathComponent("linked-config", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = LaunchAliasStore(fileURL: directory.appendingPathComponent("aliases.json"))
        try store.save(command: "work", configPath: link.path)

        XCTAssertEqual(store.alias(forConfigDir: real)?.command, "work")
        XCTAssertEqual(store.alias(forConfigDir: link)?.command, "work")
        let dotted = directory.appendingPathComponent("x/../real-config", isDirectory: true)
        XCTAssertEqual(store.alias(forConfigDir: dotted)?.command, "work")
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
