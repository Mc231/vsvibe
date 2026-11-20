import Foundation
import Observation

@MainActor
@Observable
internal final class FolderStore {
    private enum Constants {
        static let saveDelay: TimeInterval = 0.5
    }

    internal private(set) var folders: [FolderEntry] = []
    /// User-created labels, in sidebar display order.
    internal private(set) var labels: [ProjectLabel] = []
    internal private(set) var ungroupedCollapsed = false

    @ObservationIgnored private let saveDebouncer = Debouncer(interval: Constants.saveDelay)
    @ObservationIgnored private let fileURL: URL

    // MARK: - Labels

    /// The sidebar sections: one per label (in order), then the unlabelled bucket.
    internal var sidebarGroups: [SidebarGroup] {
        SidebarGrouping.groups(folders: folders, labels: labels, ungroupedCollapsed: ungroupedCollapsed)
    }

    internal init(fileURL: URL = AppPaths.stateFile) {
        self.fileURL = fileURL
        load()
    }

    @discardableResult
    internal func createProject(
        url: URL,
        name: String,
        launchCommand: String,
        labelIDs: [ProjectLabel.ID] = []
    ) -> FolderEntry {
        let resolved = url.standardizedFileURL
        if let existing = folders.first(where: { $0.url.standardizedFileURL == resolved }) {
            updateProject(id: existing.id, name: name, launchCommand: launchCommand, labelIDs: labelIDs)
            return folders.first { $0.id == existing.id } ?? existing
        }
        let entry = FolderEntry(
            url: resolved,
            displayName: name,
            launchCommand: launchCommand,
            labelIDs: sanitized(labelIDs)
        )
        folders.append(entry)
        scheduleSave()
        Log.store.info("Created project \(name, privacy: .public) at \(resolved.path, privacy: .public)")
        return entry
    }

    /// Creates a project at `location`: a local one through
    /// `createProject(url:name:launchCommand:labelIDs:)` (an existing project
    /// for that folder is updated instead), a remote one always new.
    @discardableResult
    internal func createProject(
        name: String,
        location: ProjectLocation,
        labelIDs: [ProjectLabel.ID] = []
    ) -> FolderEntry {
        switch location {
        case let .local(folder, launchCommand):
            return createProject(url: folder, name: name, launchCommand: launchCommand, labelIDs: labelIDs)

        case .remote(let target):
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = FolderEntry(
                remote: target,
                displayName: trimmedName.isEmpty ? nil : trimmedName,
                labelIDs: sanitized(labelIDs)
            )
            folders.append(entry)
            scheduleSave()
            Log.store.info("Created remote project \(entry.displayName, privacy: .public)")
            return entry
        }
    }

    /// Updates name (blank is ignored), location and labels. Turning a local
    /// project remote keeps its `url` as its identity (so its stats stay);
    /// turning a remote one local points it at the chosen folder.
    internal func updateProject(
        id: FolderEntry.ID,
        name: String,
        location: ProjectLocation,
        labelIDs: [ProjectLabel.ID]
    ) {
        guard let idx = applyNameAndCommand(id: id, name: name, launchCommand: location.launchCommand) else {
            return
        }
        folders[idx].url = location.localFolder?.standardizedFileURL ?? folders[idx].url
        folders[idx].remote = location.remote
        folders[idx].labelIDs = sanitized(labelIDs)
        scheduleSave()
    }

    /// Updates name and launch command (blank values are ignored), keeping the labels.
    internal func updateProject(id: FolderEntry.ID, name: String, launchCommand: String) {
        guard applyNameAndCommand(id: id, name: name, launchCommand: launchCommand) != nil else {
            return
        }
        scheduleSave()
    }

    /// Updates name and launch command (blank values are ignored) and replaces the labels.
    internal func updateProject(
        id: FolderEntry.ID,
        name: String,
        launchCommand: String,
        labelIDs: [ProjectLabel.ID]
    ) {
        guard let idx = applyNameAndCommand(id: id, name: name, launchCommand: launchCommand) else {
            return
        }
        folders[idx].labelIDs = sanitized(labelIDs)
        scheduleSave()
    }

    internal func remove(id: FolderEntry.ID) {
        folders.removeAll { $0.id == id }
        scheduleSave()
    }

    internal func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Creates a label, or returns the existing one when a label with the same
    /// name (case-insensitively) is already there.
    @discardableResult
    internal func createLabel(
        name: String,
        colorHex: String? = nil,
        symbolName: String = LabelPalette.defaultSymbol
    ) -> ProjectLabel? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let existing = labels.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let label = ProjectLabel(
            name: trimmed,
            colorHex: colorHex ?? LabelPalette.suggestedColor(usedBy: labels),
            symbolName: symbolName
        )
        labels.append(label)
        scheduleSave()
        Log.store.info("Created label \(trimmed, privacy: .public)")
        return label
    }

    internal func updateLabel(id: ProjectLabel.ID, name: String, colorHex: String, symbolName: String) {
        guard let idx = labels.firstIndex(where: { $0.id == id }) else {
            return
        }
        labels[idx].applyEdit(name: name, colorHex: colorHex, symbolName: symbolName)
        scheduleSave()
    }

    /// Deletes a label and detaches it from every project (the projects stay).
    internal func deleteLabel(id: ProjectLabel.ID) {
        guard labels.contains(where: { $0.id == id }) else {
            return
        }
        labels.removeAll { $0.id == id }
        for idx in folders.indices {
            folders[idx].labelIDs.removeAll { $0 == id }
        }
        scheduleSave()
        Log.store.info("Deleted label \(id.uuidString, privacy: .public)")
    }

    internal func moveLabels(fromOffsets source: IndexSet, toOffset destination: Int) {
        labels.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    internal func setLabelCollapsed(id: ProjectLabel.ID, _ collapsed: Bool) {
        guard let idx = labels.firstIndex(where: { $0.id == id }), labels[idx].isCollapsed != collapsed else {
            return
        }
        labels[idx].isCollapsed = collapsed
        scheduleSave()
    }

    internal func setUngroupedCollapsed(_ collapsed: Bool) {
        guard ungroupedCollapsed != collapsed else {
            return
        }
        ungroupedCollapsed = collapsed
        scheduleSave()
    }

    // MARK: - Label assignment

    internal func setLabels(_ ids: [ProjectLabel.ID], for folderID: FolderEntry.ID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }
        folders[idx].labelIDs = sanitized(ids)
        scheduleSave()
    }

    internal func addLabel(_ labelID: ProjectLabel.ID, to folderID: FolderEntry.ID) {
        guard labels.contains(where: { $0.id == labelID }),
            let idx = folders.firstIndex(where: { $0.id == folderID }),
            !folders[idx].labelIDs.contains(labelID)
        else {
            return
        }
        folders[idx].labelIDs.append(labelID)
        scheduleSave()
    }

    internal func removeLabel(_ labelID: ProjectLabel.ID, from folderID: FolderEntry.ID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }),
            folders[idx].labelIDs.contains(labelID)
        else {
            return
        }
        folders[idx].labelIDs.removeAll { $0 == labelID }
        scheduleSave()
    }

    internal func toggleLabel(_ labelID: ProjectLabel.ID, for folderID: FolderEntry.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else {
            return
        }
        if folder.labelIDs.contains(labelID) {
            removeLabel(labelID, from: folderID)
        } else {
            addLabel(labelID, to: folderID)
        }
    }

    internal func labels(for folder: FolderEntry) -> [ProjectLabel] {
        folder.labelIDs.compactMap { id in labels.first { $0.id == id } }
    }

    /// Reorder inside one sidebar section, preserving the global folder order
    /// for everything outside that section.
    internal func move(
        inGroupWithFolderIDs ids: [FolderEntry.ID],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        folders = FolderOrdering.move(folders: folders, groupFolderIDs: ids, fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Shared part of the `updateProject` overloads: applies the non-blank
    /// name/command and returns the project's index (nil when unknown).
    private func applyNameAndCommand(id: FolderEntry.ID, name: String, launchCommand: String) -> Int? {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCmd = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            folders[idx].displayName = trimmedName
        }
        if !trimmedCmd.isEmpty {
            folders[idx].launchCommand = trimmedCmd
        }
        return idx
    }

    /// Drops unknown ids and duplicates while keeping the caller's order.
    private func sanitized(_ ids: [ProjectLabel.ID]) -> [ProjectLabel.ID] {
        let known = Set(labels.map(\.id))
        var seen = Set<ProjectLabel.ID>()
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    private func scheduleSave() {
        let snapshot = PersistedState(
            version: PersistedState.currentVersion,
            folders: folders,
            labels: labels,
            ungroupedCollapsed: ungroupedCollapsed
        )
        let url = fileURL
        saveDebouncer.call {
            FolderStateFile.write(snapshot, to: url)
        }
    }

    private func load() {
        guard let state = FolderStateFile.read(from: fileURL) else {
            return
        }
        labels = state.labels
        ungroupedCollapsed = state.ungroupedCollapsed
        folders = state.folders
    }

    deinit {
        // Pending debounced saves hold their own snapshot; nothing to release.
    }
}
