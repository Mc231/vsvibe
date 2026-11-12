internal enum HookEventKind: String, Codable {
    case notification = "Notification"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case unknown = "unknown"

    internal var displayName: String {
        switch self {
        case .stop:
            "Claude finished"

        case .notification:
            "Claude needs input"

        case .subagentStop:
            "Subagent finished"

        case .unknown:
            "Claude event"
        }
    }

    /// Unrecognised event names decode as `.unknown` instead of failing.
    internal init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}
