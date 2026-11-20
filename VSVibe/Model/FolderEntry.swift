import Foundation

/// A project: a local folder, or a folder on another machine reached over SSH
/// (`remote`). A remote project's `url` is only its identity (stats key,
/// `state.json`): new ones get `remoteIdentityURL(for:)`, which never exists
/// locally, and it is never used as a working directory.
internal struct FolderEntry: Codable, Identifiable, Hashable {
    private enum CodingKeys: CodingKey {
        case addedAt
        case displayName
        case id
        case labelIDs
        case launchCommand
        case remote
        case url
    }

    /// Root of the synthetic identity URLs of remote projects.
    private static let remoteIdentityRoot = "/.vsvibe-remote"

    internal let id: UUID
    internal var url: URL
    internal var displayName: String
    /// Local command typed into the pane's shell (`ssh` for remote projects,
    /// whose own command is `remote.command`).
    internal var launchCommand: String
    /// Labels this project belongs to, in the order they were assigned.
    internal var labelIDs: [ProjectLabel.ID]
    internal let addedAt: Date
    /// Set for a remote (SSH) project; nil for a local folder.
    internal var remote: RemoteTarget?

    internal var isRemote: Bool { remote != nil }

    /// Where the project lives, for display: the local path or `host:folder`.
    internal var locationDescription: String {
        remote?.location ?? url.path
    }

    /// The command the project runs, where it runs: the remote command for a
    /// remote project, else the local launch command. `--continue` and
    /// restore build on it.
    internal var primaryCommand: String {
        remote?.command ?? launchCommand
    }

    /// The project's location as the editor edits it.
    internal var location: ProjectLocation {
        remote.map(ProjectLocation.remote) ?? .local(folder: url, launchCommand: launchCommand)
    }

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
        self.remote = nil
    }

    /// A new remote project, identified by `remoteIdentityURL(for: id)`.
    internal init(
        remote: RemoteTarget,
        displayName: String? = nil,
        labelIDs: [ProjectLabel.ID] = [],
        addedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.url = Self.remoteIdentityURL(for: id)
        self.displayName = displayName ?? remote.defaultDisplayName
        self.launchCommand = SSHCommand.executable
        self.labelIDs = labelIDs
        self.addedAt = addedAt
        self.remote = remote
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
        self.remote = try container.decodeIfPresent(RemoteTarget.self, forKey: .remote)
    }

    /// The identity URL of a new remote project: under a root-level directory
    /// no user can create, so it never collides with a local project (or its
    /// stats) and stays the same when the host or folder is edited.
    internal static func remoteIdentityURL(for id: UUID) -> URL {
        URL(fileURLWithPath: "\(remoteIdentityRoot)/\(id.uuidString)", isDirectory: true)
    }

    /// Whether a pane started for `other` would run something different from
    /// one started for this project (so running panes should restart).
    internal func launchesDifferently(than other: Self) -> Bool {
        launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            != other.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            || remote != other.remote
            || url.standardizedFileURL != other.url.standardizedFileURL
    }
}
