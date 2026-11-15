/// The open panes, in display order, as persisted in `sessions.json` so they
/// can be reopened on the next launch.
internal struct SessionSnapshot: Codable, Equatable {
    /// v1: `panes` + `focusedIndex`.
    /// v2: adds `panes[].transcriptPath` (v1 files still load without it).
    /// Files with a newer version are not restored (`SessionSnapshotFile.read`).
    internal static let currentVersion = 2

    internal var version: Int
    /// Panes in display order (the tiling layout is derived from this order).
    internal var panes: [PaneSnapshot]
    /// Index into `panes` of the focused pane, if any.
    internal var focusedIndex: Int?

    internal init(panes: [PaneSnapshot], focusedIndex: Int? = nil, version: Int = currentVersion) {
        self.version = version
        self.panes = panes
        self.focusedIndex = focusedIndex
    }
}
