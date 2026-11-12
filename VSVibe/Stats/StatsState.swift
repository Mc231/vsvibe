/// Root persisted stats document. Keyed by a project's standardized folder path,
/// which is the common identifier across transcripts (path-encoded), git, and
/// runtime events.
internal struct StatsState: Codable {
    internal static let currentVersion = 1

    internal var version: Int = Self.currentVersion
    internal var projects: [String: ProjectStat] = [:]
}
