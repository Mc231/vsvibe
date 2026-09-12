import Foundation

struct FolderEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var url: URL
    var displayName: String
    var launchCommand: String
    /// Labels this project belongs to, in the order they were assigned.
    var labelIDs: [ProjectLabel.ID]
    let addedAt: Date

    init(id: UUID = UUID(),
         url: URL,
         displayName: String? = nil,
         launchCommand: String? = nil,
         labelIDs: [ProjectLabel.ID] = [],
         addedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.launchCommand = launchCommand ?? LaunchCommandResolver.defaultCommand(for: url)
        self.labelIDs = labelIDs
        self.addedAt = addedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, displayName, launchCommand, labelIDs, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let url = try c.decode(URL.self, forKey: .url)
        let displayName = try c.decode(String.self, forKey: .displayName)
        let addedAt = try c.decode(Date.self, forKey: .addedAt)
        let launchCommand = try c.decodeIfPresent(String.self, forKey: .launchCommand)
            ?? LaunchCommandResolver.defaultCommand(for: url)
        self.id = id
        self.url = url
        self.displayName = displayName
        self.launchCommand = launchCommand
        self.labelIDs = try c.decodeIfPresent([ProjectLabel.ID].self, forKey: .labelIDs) ?? []
        self.addedAt = addedAt
    }
}
