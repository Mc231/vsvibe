internal enum SidebarGrouping {
    /// Builds the sidebar sections in display order: labels in their stored
    /// order, then the unlabelled bucket.
    ///
    /// - Labels with no projects are still shown, so a freshly created (or
    ///   emptied) label stays visible and manageable.
    /// - The unlabelled bucket is hidden once it is empty *and* at least one
    ///   label exists; with no labels at all it is the plain "Shortcuts" list.
    /// - Label ids on a project that no longer resolve are ignored, so a project
    ///   whose labels were all deleted falls back to the unlabelled bucket.
    internal static func groups(
        folders: [FolderEntry],
        labels: [ProjectLabel],
        ungroupedCollapsed: Bool = false
    ) -> [SidebarGroup] {
        let knownIDs = Set(labels.map(\.id))

        var result: [SidebarGroup] = labels.map { label in
            SidebarGroup(
                label: label,
                title: label.name,
                folders: folders.filter { $0.labelIDs.contains(label.id) },
                isCollapsed: label.isCollapsed
            )
        }

        let unlabelled = folders.filter { folder in
            !folder.labelIDs.contains { knownIDs.contains($0) }
        }
        if !unlabelled.isEmpty || labels.isEmpty {
            result.append(
                SidebarGroup(
                    label: nil,
                    title: labels.isEmpty ? "Shortcuts" : "Ungrouped",
                    folders: unlabelled,
                    isCollapsed: ungroupedCollapsed
                )
            )
        }
        return result
    }
}
