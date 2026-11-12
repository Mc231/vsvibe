import Foundation

internal struct FolderEntry: Codable, Identifiable, Hashable {
    private enum CodingKeys: CodingKey {
        case addedAt
        case displayName
        case id
        case labelIDs
        case launchCommand
        case url
    }

    internal let id: UUID
    internal var url: URL
    internal var displayName: String
    internal var launchCommand: String
    /// Labels this project belongs to, in the order they were assigned.
    internal var labelIDs: [ProjectLabel.ID]
    internal let addedAt: Date

    internal init(
        url: URL,
        displayName: String? = nil,
        launchCommand: String? = nil,
        labelIDs: [ProjectLabel.ID] = [],
        addedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.launchCommand = launchCommand ?? LaunchCommandResolver.defaultCommand(for: url)
        self.labelIDs = labelIDs
        self.addedAt = addedAt
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let url = try container.decode(URL.self, forKey: .url)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let addedAt = try container.decode(Date.self, forKey: .addedAt)
        let launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand)
            ?? LaunchCommandResolver.defaultCommand(for: url)
        self.id = id
        self.url = url
        self.displayName = displayName
        self.launchCommand = launchCommand
        self.labelIDs = try container.decodeIfPresent([ProjectLabel.ID].self, forKey: .labelIDs) ?? []
        self.addedAt = addedAt
    }
}
