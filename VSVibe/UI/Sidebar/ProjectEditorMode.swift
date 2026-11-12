import Foundation

internal enum ProjectEditorMode: Identifiable, Equatable {
    case create(url: URL)
    case edit(folder: FolderEntry)

    internal var id: String {
        switch self {
        case .create(let url):
            "create:\(url.path)"

        case .edit(let folder):
            "edit:\(folder.id.uuidString)"
        }
    }

    internal var isCreate: Bool {
        if case .create = self {
            return true
        }
        return false
    }
}
