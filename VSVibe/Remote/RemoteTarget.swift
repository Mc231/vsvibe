import Foundation

/// Where a remote (SSH) project lives and what its panes run there. A pane of
/// such a project opens a local shell and types the `ssh` line built by
/// `SSHCommand` (see docs/remote-projects.md).
internal struct RemoteTarget: Codable, Hashable {
    private enum CodingKeys: CodingKey {
        case command
        case destination
        case port
        case remotePath
        case runsClaude
    }

    /// `~/.ssh/config` Host alias, `host` or `user@host` (validated by `SSHCommand`).
    internal var destination: String
    /// SSH port; nil uses ssh's default (or the `~/.ssh/config` entry).
    internal var port: Int?
    /// Remote folder: absolute, relative to the remote home, `~` or `~/…`;
    /// empty stays in the remote home.
    internal var remotePath: String
    /// Command run in the remote folder (an interactive login shell resolves
    /// it, so remote aliases work); empty opens just that shell.
    internal var command: String
    /// The user's "Runs Claude" choice: the pane pre-assigns the conversation
    /// id (`--session-id`) and resumes it on restore. See `launchesClaude`.
    internal var runsClaude: Bool

    /// `destination` without the `user@` part.
    internal var host: String {
        destination.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? destination
    }

    /// Whether panes run a Claude conversation: "Runs Claude" is on and there
    /// is a command (an empty command is a plain shell).
    internal var launchesClaude: Bool {
        runsClaude && !trimmedCommand.isEmpty
    }

    /// `destination:remotePath` (or just the destination), for display.
    internal var location: String {
        remotePath.isEmpty ? destination : "\(destination):\(remotePath)"
    }

    /// `<remote folder name> (<host>)`, or the host alone without a folder.
    internal var defaultDisplayName: String {
        let folderName = remotePath.split(separator: "/").last.map(String.init) ?? ""
        guard !folderName.isEmpty, folderName != "~" else {
            return host
        }
        return "\(folderName) (\(host))"
    }

    internal var trimmedCommand: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal init(
        destination: String,
        port: Int? = nil,
        remotePath: String = "",
        command: String = LaunchCommandResolver.defaultCommand,
        runsClaude: Bool = true
    ) {
        self.destination = destination
        self.port = port
        self.remotePath = remotePath
        self.command = command
        self.runsClaude = runsClaude
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.destination = try container.decode(String.self, forKey: .destination)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port)
        self.remotePath = try container.decodeIfPresent(String.self, forKey: .remotePath) ?? ""
        self.command = try container.decodeIfPresent(String.self, forKey: .command)
            ?? LaunchCommandResolver.defaultCommand
        self.runsClaude = try container.decodeIfPresent(Bool.self, forKey: .runsClaude) ?? true
    }
}
