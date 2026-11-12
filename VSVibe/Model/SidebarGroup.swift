import Foundation

/// One sidebar section: a label and the projects carrying it, or the trailing
/// "unlabelled" bucket (`label == nil`).
struct SidebarGroup: Identifiable, Equatable {
    static let ungroupedID = "__ungrouped__"

    let label: ProjectLabel?
    let title: String
    let folders: [FolderEntry]
    let isCollapsed: Bool

    var id: String { label?.id.uuidString ?? Self.ungroupedID }
    var isUngrouped: Bool { label == nil }
}

/// Identifies a row in the sidebar. A project can appear under several labels,
/// so the selection has to be qualified by the section it was picked in —
/// otherwise multiple rows would share a tag.
struct SidebarRowID: Hashable {
    let groupID: String
    let folderID: FolderEntry.ID
}

enum SidebarGrouping {
    /// Builds the sidebar sections in display order: labels in their stored
    /// order, then the unlabelled bucket.
    ///
    /// - Labels with no projects are still shown, so a freshly created (or
    ///   emptied) label stays visible and manageable.
    /// - The unlabelled bucket is hidden once it is empty *and* at least one
    ///   label exists; with no labels at all it is the plain "Shortcuts" list.
    /// - Label ids on a project that no longer resolve are ignored, so a project
    ///   whose labels were all deleted falls back to the unlabelled bucket.
    static func groups(folders: [FolderEntry],
                       labels: [ProjectLabel],
                       ungroupedCollapsed: Bool = false) -> [SidebarGroup] {
        let knownIDs = Set(labels.map(\.id))

        var result: [SidebarGroup] = labels.map { label in
            SidebarGroup(label: label,
                         title: label.name,
                         folders: folders.filter { $0.labelIDs.contains(label.id) },
                         isCollapsed: label.isCollapsed)
        }

        let unlabelled = folders.filter { folder in
            !folder.labelIDs.contains { knownIDs.contains($0) }
        }
        if !unlabelled.isEmpty || labels.isEmpty {
            result.append(SidebarGroup(label: nil,
                                       title: labels.isEmpty ? "Shortcuts" : "Ungrouped",
                                       folders: unlabelled,
                                       isCollapsed: ungroupedCollapsed))
        }
        return result
    }
}

enum FolderOrdering {
    /// Applies a drag-reorder that happened *inside one sidebar section* to the
    /// global folder order. The moved projects take over the slots the section's
    /// projects already occupied, leaving every other project where it was.
    static func move(folders: [FolderEntry],
                     groupFolderIDs: [FolderEntry.ID],
                     fromOffsets source: IndexSet,
                     toOffset destination: Int) -> [FolderEntry] {
        let idSet = Set(groupFolderIDs)
        let slots = folders.indices.filter { idSet.contains(folders[$0].id) }
        guard slots.count > 1 else { return folders }

        var section = slots.map { folders[$0] }
        section.move(fromOffsets: source, toOffset: destination)

        var result = folders
        for (offset, slot) in slots.enumerated() {
            result[slot] = section[offset]
        }
        return result
    }
}
