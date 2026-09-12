import Foundation

struct PersistedState: Codable {
    var version: Int
    var folders: [FolderEntry]
    /// User-created labels, in sidebar display order.
    var labels: [ProjectLabel]
    /// Collapsed state of the trailing "Ungrouped" section.
    var ungroupedCollapsed: Bool

    /// v1: folders only. v2: adds `labels` / `ungroupedCollapsed` and
    /// `FolderEntry.labelIDs`. v1 files decode as v2 with no labels.
    static let currentVersion = 2
    static let empty = PersistedState(version: currentVersion, folders: [])

    init(version: Int,
         folders: [FolderEntry],
         labels: [ProjectLabel] = [],
         ungroupedCollapsed: Bool = false) {
        self.version = version
        self.folders = folders
        self.labels = labels
        self.ungroupedCollapsed = ungroupedCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case version, folders, labels, ungroupedCollapsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.folders = try c.decode([FolderEntry].self, forKey: .folders)
        self.labels = try c.decodeIfPresent([ProjectLabel].self, forKey: .labels) ?? []
        self.ungroupedCollapsed = try c.decodeIfPresent(Bool.self, forKey: .ungroupedCollapsed) ?? false
    }
}
