@testable import VSVibe
import XCTest

/// Runs the real hook script with macOS `/bin/bash` (3.2) the way Claude does:
/// event name as `$1`, JSON payload on stdin. `HOME` points at a temp
/// directory, so events land in `<temp>/.vsvibe/events.jsonl`.
@MainActor
internal final class HookScriptTests: XCTestCase {
    private struct Run {
        let status: Int32
        let stdout: String
    }

    private var home = FileManager.default.temporaryDirectory

    private var scriptURL: URL { home.appendingPathComponent("hooks/claude-notify.sh") }
    private var eventsURL: URL { home.appendingPathComponent(".vsvibe/events.jsonl") }

    override internal func setUp() {
        super.setUp()
        home = TestSupport.makeTempDir("hook-script")
    }

    override internal func tearDown() {
        TestSupport.remove(home)
        super.tearDown()
    }

    private func run(_ event: String, stdin: String, environment extra: [String: String] = [:]) throws -> Run {
        try HookInstaller.writeScript(to: scriptURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, event]
        var environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment.merge(extra) { _, new in new }
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, stdout: String(bytes: data, encoding: .utf8) ?? "")
    }

    private func events() throws -> [HookEvent] {
        let text = try String(contentsOf: eventsURL, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try JSONDecoder().decode(HookEvent.self, from: Data(line.utf8))
        }
    }

    internal func testScriptDeclaresItsVersion() {
        XCTAssertTrue(HookScript.contents.contains("# version: \(HookScript.version)\n"))
    }

    internal func testRecordsPaneIDSessionIDAndMessage() throws {
        let paneID = UUID()
        let payload = #"{"session_id":"abc-123","message":"Allow \"rm\"?\nnow ü","hook_event_name":"Notification","#
            + #""transcript_path":"/Users/u/.claude-work/projects/-a-b/abc-123.jsonl"}"#

        let result = try run(
            "Notification",
            stdin: payload,
            environment: ["VSVIBE_PANE_ID": paneID.uuidString, "CLAUDE_PROJECT_DIR": "/tmp/a \"b\"/c"]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "", "SessionStart hook output would be added to Claude's context")
        let event = try XCTUnwrap(try events().first)
        XCTAssertEqual(event.event, .notification)
        XCTAssertEqual(event.paneID, paneID)
        XCTAssertEqual(event.claudeSessionID, "abc-123")
        XCTAssertEqual(event.transcriptPath, "/Users/u/.claude-work/projects/-a-b/abc-123.jsonl")
        XCTAssertEqual(event.message, "Allow \"rm\"?\nnow ü")
        XCTAssertEqual(event.projectDir, "/tmp/a \"b\"/c")
        XCTAssertGreaterThan(event.timestamp, 0)
    }

    internal func testSessionStartWithoutPaneOrPayload() throws {
        let result = try run("SessionStart", stdin: "", environment: ["CLAUDE_PROJECT_DIR": "/p"])

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "")
        let event = try XCTUnwrap(try events().first)
        XCTAssertEqual(event.event, .sessionStart)
        XCTAssertNil(event.paneID)
        XCTAssertNil(event.claudeSessionID)
        XCTAssertNil(event.transcriptPath)
        XCTAssertEqual(event.message, "")
    }

    internal func testNonJSONPayloadStillWritesAValidLine() throws {
        _ = try run("Stop", stdin: "not json", environment: ["CLAUDE_PROJECT_DIR": "/p"])
        _ = try run("Stop", stdin: "[1, 2]", environment: ["CLAUDE_PROJECT_DIR": "/p"])

        let recorded = try events()
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded.map(\.event), [.stop, .stop])
        XCTAssertNil(recorded.first?.claudeSessionID)
        XCTAssertNil(recorded.first?.transcriptPath)
    }

    internal func testTranscriptPathWithSpecialCharactersRoundTrips() throws {
        let path = #"/Users/u/My "Claude" ü/projects/-p/s-1.jsonl"#
        let payload = try JSONSerialization.data(withJSONObject: ["session_id": "s-1", "transcript_path": path])

        let result = try run("SessionStart", stdin: String(bytes: payload, encoding: .utf8) ?? "")

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "")
        let event = try XCTUnwrap(try events().first)
        XCTAssertEqual(event.claudeSessionID, "s-1")
        XCTAssertEqual(event.transcriptPath, path)
    }

    deinit {
        // Temp directories are removed in tearDown.
    }
}
