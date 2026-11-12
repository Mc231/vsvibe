/// Identifies a row in the sidebar. A project can appear under several labels,
/// so the selection has to be qualified by the section it was picked in —
/// otherwise multiple rows would share a tag.
internal struct SidebarRowID: Hashable {
    internal let groupID: String
    internal let folderID: FolderEntry.ID
}
