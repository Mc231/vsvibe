import Foundation

enum HookEventKind: String, Codable {
    case stop = "Stop"
    case notification = "Notification"
    case subagentStop = "SubagentStop"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = HookEventKind(rawValue: raw) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .stop: "Claude finished"
        case .notification: "Claude needs input"
        case .subagentStop: "Subagent finished"
        case .unknown: "Claude event"
        }
    }
}

struct HookEvent: Codable, Identifiable {
    let id: UUID
    let event: HookEventKind
    let projectDir: String
    let ts: TimeInterval
    let message: String?

    enum CodingKeys: String, CodingKey {
        case event, projectDir, ts, payload, message
    }

    init(event: HookEventKind, projectDir: String, ts: TimeInterval, message: String?) {
        self.id = UUID()
        self.event = event
        self.projectDir = projectDir
        self.ts = ts
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.event = (try? c.decode(HookEventKind.self, forKey: .event)) ?? .unknown
        self.projectDir = (try? c.decode(String.self, forKey: .projectDir)) ?? ""
        self.ts = (try? c.decode(TimeInterval.self, forKey: .ts)) ?? Date().timeIntervalSince1970
        if let msg = try? c.decode(String.self, forKey: .message) {
            self.message = msg
        } else if let payload = try? c.decode(HookPayload.self, forKey: .payload) {
            self.message = payload.message
        } else {
            self.message = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event.rawValue, forKey: .event)
        try c.encode(projectDir, forKey: .projectDir)
        try c.encode(ts, forKey: .ts)
        try c.encodeIfPresent(message, forKey: .message)
    }
}

/// Subset of the JSON payload Claude passes on stdin to hook commands.
private struct HookPayload: Codable {
    let message: String?
}
