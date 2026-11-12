import Foundation

internal struct HookEvent: Codable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case event = "event"
        case message = "message"
        case payload = "payload"
        case projectDir = "projectDir"
        case timestamp = "ts"
    }

    /// Subset of the JSON payload Claude passes on stdin to hook commands.
    private struct HookPayload: Codable {
        let message: String?
    }

    internal let id: UUID
    internal let event: HookEventKind
    internal let projectDir: String
    /// Seconds since 1970 (the `ts` field written by the hook script).
    internal let timestamp: TimeInterval
    internal let message: String?

    internal init(event: HookEventKind, projectDir: String, timestamp: TimeInterval, message: String?) {
        self.id = UUID()
        self.event = event
        self.projectDir = projectDir
        self.timestamp = timestamp
        self.message = message
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.event = (try? container.decode(HookEventKind.self, forKey: .event)) ?? .unknown
        self.projectDir = (try? container.decode(String.self, forKey: .projectDir)) ?? ""
        self.timestamp = (try? container.decode(TimeInterval.self, forKey: .timestamp)) ?? Date().timeIntervalSince1970
        if let message = try? container.decode(String.self, forKey: .message) {
            self.message = message
        } else if let payload = try? container.decode(HookPayload.self, forKey: .payload) {
            self.message = payload.message
        } else {
            self.message = nil
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event.rawValue, forKey: .event)
        try container.encode(projectDir, forKey: .projectDir)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(message, forKey: .message)
    }
}
