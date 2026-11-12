import Foundation

internal enum FolderOrdering {
    /// Applies a drag-reorder that happened *inside one sidebar section* to the
    /// global folder order. The moved projects take over the slots the section's
    /// projects already occupied, leaving every other project where it was.
    internal static func move(
        folders: [FolderEntry],
        groupFolderIDs: [FolderEntry.ID],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [FolderEntry] {
        let idSet = Set(groupFolderIDs)
        let slots = folders.indices.filter { idSet.contains(folders[$0].id) }
        guard slots.count > 1 else {
            return folders
        }

        var section = slots.map { folders[$0] }
        section.move(fromOffsets: source, toOffset: destination)

        var result = folders
        for (offset, slot) in slots.enumerated() {
            result[slot] = section[offset]
        }
        return result
    }
}
