import Foundation

internal enum LabelEditorMode: Identifiable, Equatable {
    /// Create a label; when `assignTo` is set the new label is applied to that
    /// project right away (used by the row context menu).
    case create(assignTo: FolderEntry.ID?)
    case edit(label: ProjectLabel)

    internal var id: String {
        switch self {
        case .create(let assignTo):
            "create:\(assignTo?.uuidString ?? "-")"

        case .edit(let label):
            "edit:\(label.id.uuidString)"
        }
    }

    internal var isCreate: Bool {
        if case .create = self {
            return true
        }
        return false
    }
}
