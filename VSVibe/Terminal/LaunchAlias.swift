import Foundation

internal struct LaunchAlias: Codable, Identifiable, Hashable {
    internal let command: String
    /// Claude-style settings.json config directory. `nil` if this alias does
    /// not use the Claude hooks system (e.g. opencode).
    internal let claudeConfigDir: URL?

    internal var id: String { command }
    internal var supportsClaudeHooks: Bool { claudeConfigDir != nil }
    internal var settingsURL: URL? { claudeConfigDir?.appendingPathComponent("settings.json") }
}
