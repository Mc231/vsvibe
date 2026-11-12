internal struct PersistedState: Codable {
    private enum CodingKeys: CodingKey {
        case folders
        case labels
        case ungroupedCollapsed
        case version
    }

    /// v1: folders only. v2: adds `labels` / `ungroupedCollapsed` and
    /// `FolderEntry.labelIDs`. v1 files decode as v2 with no labels.
    internal static let currentVersion = 2
    internal static let empty = Self(version: currentVersion, folders: [])

    internal var version: Int
    internal var folders: [FolderEntry]
    /// User-created labels, in sidebar display order.
    internal var labels: [ProjectLabel]
    /// Collapsed state of the trailing "Ungrouped" section.
    internal var ungroupedCollapsed: Bool

    internal init(
        version: Int,
        folders: [FolderEntry],
        labels: [ProjectLabel] = [],
        ungroupedCollapsed: Bool = false
    ) {
        self.version = version
        self.folders = folders
        self.labels = labels
        self.ungroupedCollapsed = ungroupedCollapsed
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.folders = try container.decode([FolderEntry].self, forKey: .folders)
        self.labels = try container.decodeIfPresent([ProjectLabel].self, forKey: .labels) ?? []
        self.ungroupedCollapsed = try container.decodeIfPresent(Bool.self, forKey: .ungroupedCollapsed) ?? false
    }
}
