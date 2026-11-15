import Foundation

/// One line of `~/.vsvibe/events.jsonl`, written by the hook script.
/// Every field is optional on decode, so lines from older scripts (no
/// `paneId` / `sessionId` / `transcriptPath`) still decode.
internal struct HookEvent: Codable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case claudeSessionID = "sessionId"
        case event = "event"
        case message = "message"
        case paneID = "paneId"
        case payload = "payload"
        case projectDir = "projectDir"
        case timestamp = "ts"
        case transcriptPath = "transcriptPath"
    }

    /// Subset of the JSON payload Claude passes on stdin to hook commands.
    private enum PayloadKeys: String, CodingKey {
        case message = "message"
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
    }

    internal let id: UUID
    internal let event: HookEventKind
    internal let projectDir: String
    /// Seconds since 1970 (the `ts` field written by the hook script).
    internal let timestamp: TimeInterval
    internal let message: String?
    /// The VSVibe pane (`TerminalSession.id`) whose shell ran Claude, from the
    /// `VSVIBE_PANE_ID` environment variable. Nil for events from other
    /// terminals and from hook scripts older than v2.
    internal let paneID: UUID?
    /// Claude's `session_id` (the conversation), nil when unknown.
    internal let claudeSessionID: String?
    /// Claude's `transcript_path`: the conversation's `.jsonl` file under
    /// `<config dir>/projects/`. Nil when unknown (hook scripts older than v3).
    internal let transcriptPath: String?

    internal init(
        event: HookEventKind,
        projectDir: String,
        timestamp: TimeInterval,
        message: String?,
        paneID: UUID? = nil,
        claudeSessionID: String? = nil,
        transcriptPath: String? = nil
    ) {
        self.id = UUID()
        self.event = event
        self.projectDir = projectDir
        self.timestamp = timestamp
        self.message = message
        self.paneID = paneID
        self.claudeSessionID = claudeSessionID
        self.transcriptPath = transcriptPath
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try? container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
        self.id = UUID()
        self.event = (try? container.decode(HookEventKind.self, forKey: .event)) ?? .unknown
        self.projectDir = (try? container.decode(String.self, forKey: .projectDir)) ?? ""
        self.timestamp = (try? container.decode(TimeInterval.self, forKey: .timestamp)) ?? Date().timeIntervalSince1970
        if let message = try? container.decode(String.self, forKey: .message) {
            self.message = message
        } else {
            self.message = try? payload?.decode(String.self, forKey: .message)
        }
        self.paneID = (try? container.decode(String.self, forKey: .paneID)).flatMap(UUID.init(uuidString:))
        let topLevelSessionID = Self.nonEmpty(try? container.decode(String.self, forKey: .claudeSessionID))
        self.claudeSessionID = topLevelSessionID
            ?? Self.nonEmpty(try? payload?.decode(String.self, forKey: .sessionID))
        self.transcriptPath = Self.nonEmpty(try? container.decode(String.self, forKey: .transcriptPath))
            ?? Self.nonEmpty(try? payload?.decode(String.self, forKey: .transcriptPath))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event.rawValue, forKey: .event)
        try container.encode(projectDir, forKey: .projectDir)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(paneID?.uuidString, forKey: .paneID)
        try container.encodeIfPresent(claudeSessionID, forKey: .claudeSessionID)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
    }
}
