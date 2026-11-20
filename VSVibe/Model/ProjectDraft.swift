import Foundation

/// The project editor's fields as typed: name, Local / Remote (SSH) choice,
/// the local folder and launch command, and the remote fields. Turns them
/// into the `ProjectLocation` to save, so the editor view holds no logic.
internal struct ProjectDraft: Equatable {
    internal var name = ""
    /// The Local / Remote (SSH) choice.
    internal var isRemote = false
    /// The local folder; nil until one is chosen (a new remote project
    /// switched to local, or a remote project being turned local).
    internal var localFolder: URL?
    internal var launchCommand = LaunchCommandResolver.defaultCommand
    internal var remote = RemoteProjectForm()

    /// What to save: nil while the fields are incomplete or invalid.
    internal var location: ProjectLocation? {
        if isRemote {
            guard case .success(let target) = remote.target else {
                return nil
            }
            return .remote(target)
        }
        guard let localFolder, !trimmedLaunchCommand.isEmpty else {
            return nil
        }
        return .local(folder: localFolder, launchCommand: trimmedLaunchCommand)
    }

    /// The typed name, or for a remote project left blank the name derived
    /// from its host and folder.
    internal var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty && isRemote ? remote.suggestedName : trimmed
    }

    internal var canSave: Bool {
        location != nil && !effectiveName.isEmpty
    }

    /// The editor's subtitle: where the project lives.
    internal var subtitle: String {
        if isRemote {
            let destination = remote.destination.trimmingCharacters(in: .whitespaces)
            return destination.isEmpty ? "Remote (SSH)" : "ssh \(destination)"
        }
        return localFolder?.path ?? "Choose a folder"
    }

    internal var trimmedLaunchCommand: String {
        launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A new local project for `folder`.
    internal init(creatingAt folder: URL) {
        name = folder.lastPathComponent
        localFolder = folder
        launchCommand = LaunchCommandResolver.defaultCommand(for: folder)
    }

    /// A new remote project (blank host; the name follows host and folder).
    internal init() {
        isRemote = true
    }

    /// The fields of an existing project.
    internal init(editing folder: FolderEntry) {
        name = folder.displayName
        if let target = folder.remote {
            isRemote = true
            remote = RemoteProjectForm(target: target)
        } else {
            localFolder = folder.url
            launchCommand = folder.launchCommand
        }
    }
}
