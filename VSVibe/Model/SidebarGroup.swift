import Foundation

/// One sidebar section: a label and the projects carrying it, or the trailing
/// "unlabelled" bucket (`label == nil`).
internal struct SidebarGroup: Identifiable, Equatable {
    internal static let ungroupedID = "__ungrouped__"

    internal let label: ProjectLabel?
    internal let title: String
    internal let folders: [FolderEntry]
    internal let isCollapsed: Bool

    internal var id: String { label?.id.uuidString ?? Self.ungroupedID }
    internal var isUngrouped: Bool { label == nil }
}
