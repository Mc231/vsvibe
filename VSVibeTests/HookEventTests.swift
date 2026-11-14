@testable import VSVibe
import XCTest

internal final class HookEventTests: XCTestCase {
    private func decode(_ json: String) throws -> HookEvent {
        try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    internal func testDecodesHookScriptLine() throws {
        let event = try decode(#"{"event":"Stop","projectDir":"/tmp/demo","ts":1700000000,"message":"done"}"#)
        XCTAssertEqual(event.event, .stop)
        XCTAssertEqual(event.projectDir, "/tmp/demo")
        XCTAssertEqual(event.timestamp, 1_700_000_000)
        XCTAssertEqual(event.message, "done")
    }

    internal func testMessageFallsBackToPayload() throws {
        let event = try decode(#"{"event":"Notification","projectDir":"/x","ts":1,"payload":{"message":"hi"}}"#)
        XCTAssertEqual(event.event, .notification)
        XCTAssertEqual(event.message, "hi")
    }

    internal func testMissingFieldsUseDefaults() throws {
        let before = Date().timeIntervalSince1970
        let event = try decode("{}")
        XCTAssertEqual(event.event, .unknown)
        XCTAssertEqual(event.projectDir, "")
        XCTAssertNil(event.message)
        XCTAssertGreaterThanOrEqual(event.timestamp, before)
    }

    internal func testUnknownEventNameDecodesAsUnknown() throws {
        XCTAssertEqual(try decode(#"{"event":"PreToolUse"}"#).event, .unknown)
        XCTAssertEqual(try decode(#"{"event":"SubagentStop"}"#).event, .subagentStop)
    }

    internal func testEachDecodeGetsAFreshID() throws {
        let json = #"{"event":"Stop"}"#
        XCTAssertNotEqual(try decode(json).id, try decode(json).id)
    }

    internal func testEncodeRoundTripsAndOmitsNilMessage() throws {
        let original = HookEvent(event: .subagentStop, projectDir: "/p", timestamp: 42, message: nil)
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["event"] as? String, "SubagentStop")
        XCTAssertEqual(object["ts"] as? Double, 42)
        XCTAssertNil(object["message"])

        let decoded = try JSONDecoder().decode(HookEvent.self, from: data)
        XCTAssertEqual(decoded.event, .subagentStop)
        XCTAssertEqual(decoded.projectDir, "/p")
        XCTAssertEqual(decoded.timestamp, 42)
        XCTAssertNil(decoded.message)
    }

    internal func testEncodeKeepsMessage() throws {
        let original = HookEvent(event: .notification, projectDir: "/p", timestamp: 1, message: "wait")
        let decoded = try JSONDecoder().decode(HookEvent.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.message, "wait")
    }

    internal func testDecodesPaneAndClaudeSessionIDs() throws {
        let pane = UUID()
        let event = try decode(
            #"{"event":"SessionStart","projectDir":"/p","ts":1,"#
                + #""paneId":"\#(pane.uuidString)","sessionId":"s-1"}"#
        )
        XCTAssertEqual(event.event, .sessionStart)
        XCTAssertEqual(event.paneID, pane)
        XCTAssertEqual(event.claudeSessionID, "s-1")
    }

    internal func testEmptyOrMalformedIDsDecodeAsNil() throws {
        let event = try decode(#"{"event":"Stop","paneId":"not-a-uuid","sessionId":""}"#)
        XCTAssertNil(event.paneID)
        XCTAssertNil(event.claudeSessionID)
        let legacy = try decode(#"{"event":"Stop","projectDir":"/p","ts":1,"message":"done"}"#)
        XCTAssertNil(legacy.paneID)
        XCTAssertNil(legacy.claudeSessionID)
    }

    internal func testClaudeSessionIDFallsBackToPayload() throws {
        let event = try decode(#"{"event":"Stop","sessionId":"","payload":{"session_id":"from-payload"}}"#)
        XCTAssertEqual(event.claudeSessionID, "from-payload")
        XCTAssertNil(event.message)
    }

    internal func testEncodeRoundTripsIDs() throws {
        let pane = UUID()
        let original = HookEvent(
            event: .stop,
            projectDir: "/p",
            timestamp: 1,
            message: nil,
            paneID: pane,
            claudeSessionID: "s-2"
        )
        let decoded = try JSONDecoder().decode(HookEvent.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.paneID, pane)
        XCTAssertEqual(decoded.claudeSessionID, "s-2")
    }

    internal func testKindDisplayNames() {
        XCTAssertEqual(HookEventKind.sessionStart.displayName, "Claude session started")
        XCTAssertEqual(HookEventKind.stop.displayName, "Claude finished")
        XCTAssertEqual(HookEventKind.notification.displayName, "Claude needs input")
        XCTAssertEqual(HookEventKind.subagentStop.displayName, "Subagent finished")
        XCTAssertEqual(HookEventKind.unknown.displayName, "Claude event")
    }

    internal func testKindRawValuesMatchClaudeHookNames() {
        XCTAssertEqual(HookEventKind.stop.rawValue, "Stop")
        XCTAssertEqual(HookEventKind.notification.rawValue, "Notification")
        XCTAssertEqual(HookEventKind.subagentStop.rawValue, "SubagentStop")
    }

    deinit {
        // Stateless tests.
    }
}
