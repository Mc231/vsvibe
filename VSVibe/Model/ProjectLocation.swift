import Foundation

/// Where a project runs, as chosen in the project editor.
internal enum ProjectLocation: Equatable {
    /// A local folder and the command typed into the pane's shell there.
    case local(folder: URL, launchCommand: String)
    /// A folder on another machine, reached over SSH.
    case remote(RemoteTarget)

    /// The command typed into the pane's local shell: the launch command, or
    /// `ssh` for a remote project (the remote command is in its target).
    internal var launchCommand: String {
        switch self {
        case let .local(_, launchCommand):
            launchCommand

        case .remote:
            SSHCommand.executable
        }
    }

    /// The local folder; nil for a remote project.
    internal var localFolder: URL? {
        if case let .local(folder, _) = self {
            return folder
        }
        return nil
    }

    /// The remote target; nil for a local project.
    internal var remote: RemoteTarget? {
        if case .remote(let target) = self {
            return target
        }
        return nil
    }
}
