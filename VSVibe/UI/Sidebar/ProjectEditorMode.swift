import Foundation

internal enum ProjectEditorMode: Identifiable, Equatable {
    /// A new local project for the chosen folder.
    case create(url: URL)
    /// A new remote (SSH) project.
    case createRemote
    case edit(folder: FolderEntry)

    internal var id: String {
        switch self {
        case .create(let url):
            "create:\(url.path)"

        case .createRemote:
            "create-remote"

        case .edit(let folder):
            "edit:\(folder.id.uuidString)"
        }
    }

    internal var isCreate: Bool {
        if case .edit = self {
            return false
        }
        return true
    }
}
