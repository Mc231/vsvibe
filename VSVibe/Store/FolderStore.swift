import Foundation
import Observation

@MainActor
@Observable
final class FolderStore {
    private(set) var folders: [FolderEntry] = []
    /// User-created labels, in sidebar display order.
    private(set) var labels: [ProjectLabel] = []
    private(set) var ungroupedCollapsed: Bool = false

    @ObservationIgnored private let saveDebouncer = Debouncer(interval: 0.5)
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL = AppPaths.stateFile) {
        self.fileURL = fileURL
        load()
    }

    func add(url: URL) {
        let resolved = url.standardizedFileURL
        if folders.contains(where: { $0.url.standardizedFileURL == resolved }) {
            Log.store.info("Folder already in list: \(resolved.path, privacy: .public)")
            return
        }
        let entry = FolderEntry(url: resolved)
        folders.append(entry)
        scheduleSave()
        Log.store.info("Added folder: \(resolved.path, privacy: .public)")
    }

    @discardableResult
    func createProject(url: URL,
                       name: String,
                       launchCommand: String,
                       labelIDs: [ProjectLabel.ID] = []) -> FolderEntry {
        let resolved = url.standardizedFileURL
        if let existing = folders.first(where: { $0.url.standardizedFileURL == resolved }) {
            updateProject(id: existing.id, name: name, launchCommand: launchCommand, labelIDs: labelIDs)
            return folders.first { $0.id == existing.id }?? existing
        }
        let entry = FolderEntry(url: resolved,
                                displayName: name,
                                launchCommand: launchCommand,
                                labelIDs: sanitized(labelIDs))
        folders.append(entry)
        scheduleSave()
        Log.store.info("Created project \(name, privacy: .public) at \(resolved.path, privacy: .public)")
        return entry
    }

    func updateProject(id: FolderEntry.ID,
                       name: String,
                       launchCommand: String,
                       labelIDs: [ProjectLabel.ID]? = nil) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCmd = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { folders[idx].displayName = trimmedName }
        if !trimmedCmd.isEmpty { folders[idx].launchCommand = trimmedCmd }
        if let labelIDs { folders[idx].labelIDs = sanitized(labelIDs) }
        scheduleSave()
    }

    func remove(id: FolderEntry.ID) {
        folders.removeAll { $0.id == id }
        scheduleSave()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func rename(id: FolderEntry.ID, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].displayName = newName
        scheduleSave()
    }

    func setLaunchCommand(id: FolderEntry.ID, to command: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folders[idx].launchCommand = trimmed
        scheduleSave()
    }

    func contains(url: URL) -> Bool {
        let resolved = url.standardizedFileURL
        return folders.contains { $0.url.standardizedFileURL == resolved }
    }

    // MARK: - Labels

    /// The sidebar sections: one per label (in order), then the unlabelled bucket.
    var sidebarGroups: [SidebarGroup] {
        SidebarGrouping.groups(folders: folders,
                               labels: labels,
                               ungroupedCollapsed: ungroupedCollapsed)
    }

    func label(id: ProjectLabel.ID) -> ProjectLabel? {
        labels.first { $0.id == id }
    }

    /// Creates a label, or returns the existing one when a label with the same
    /// name (case-insensitively) is already there.
    @discardableResult
    func createLabel(name: String,
                     colorHex: String? = nil,
                     symbolName: String = LabelPalette.defaultSymbol) -> ProjectLabel? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = labels.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let label = ProjectLabel(name: trimmed,
                                 colorHex: colorHex ?? LabelPalette.suggestedColor(usedBy: labels),
                                 symbolName: symbolName)
        labels.append(label)
        scheduleSave()
        Log.store.info("Created label \(trimmed, privacy: .public)")
        return label
    }

    func updateLabel(id: ProjectLabel.ID, name: String, colorHex: String, symbolName: String) {
        guard let idx = labels.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { labels[idx].name = trimmed }
        if let hex = ColorHex.normalized(colorHex) { labels[idx].colorHex = hex }
        if !symbolName.isEmpty { labels[idx].symbolName = symbolName }
        scheduleSave()
    }

    /// Deletes a label and detaches it from every project (the projects stay).
    func deleteLabel(id: ProjectLabel.ID) {
        guard labels.contains(where: { $0.id == id }) else { return }
        labels.removeAll { $0.id == id }
        for idx in folders.indices {
            folders[idx].labelIDs.removeAll { $0 == id }
        }
        scheduleSave()
        Log.store.info("Deleted label \(id.uuidString, privacy: .public)")
    }

    func moveLabels(fromOffsets source: IndexSet, toOffset destination: Int) {
        labels.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func setLabelCollapsed(id: ProjectLabel.ID, _ collapsed: Bool) {
        guard let idx = labels.firstIndex(where: { $0.id == id }), labels[idx].isCollapsed != collapsed else { return }
        labels[idx].isCollapsed = collapsed
        scheduleSave()
    }

    func setUngroupedCollapsed(_ collapsed: Bool) {
        guard ungroupedCollapsed != collapsed else { return }
        ungroupedCollapsed = collapsed
        scheduleSave()
    }

    // MARK: - Label assignment

    func setLabels(_ ids: [ProjectLabel.ID], for folderID: FolderEntry.ID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].labelIDs = sanitized(ids)
        scheduleSave()
    }

    func addLabel(_ labelID: ProjectLabel.ID, to folderID: FolderEntry.ID) {
        guard labels.contains(where: { $0.id == labelID }),
              let idx = folders.firstIndex(where: { $0.id == folderID }),
              !folders[idx].labelIDs.contains(labelID)
        else { return }
        folders[idx].labelIDs.append(labelID)
        scheduleSave()
    }

    func removeLabel(_ labelID: ProjectLabel.ID, from folderID: FolderEntry.ID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }),
              folders[idx].labelIDs.contains(labelID)
        else { return }
        folders[idx].labelIDs.removeAll { $0 == labelID }
        scheduleSave()
    }

    func toggleLabel(_ labelID: ProjectLabel.ID, for folderID: FolderEntry.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        if folder.labelIDs.contains(labelID) {
            removeLabel(labelID, from: folderID)
        } else {
            addLabel(labelID, to: folderID)
        }
    }

    func labels(for folder: FolderEntry) -> [ProjectLabel] {
        folder.labelIDs.compactMap { id in labels.first { $0.id == id } }
    }

    /// Drops unknown ids and duplicates while keeping the caller's order.
    private func sanitized(_ ids: [ProjectLabel.ID]) -> [ProjectLabel.ID] {
        let known = Set(labels.map(\.id))
        var seen = Set<ProjectLabel.ID>()
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// Reorder inside one sidebar section, preserving the global folder order
    /// for everything outside that section.
    func move(inGroupWithFolderIDs ids: [FolderEntry.ID],
              fromOffsets source: IndexSet,
              toOffset destination: Int) {
        folders = FolderOrdering.move(folders: folders,
                                      groupFolderIDs: ids,
                                      fromOffsets: source,
                                      toOffset: destination)
        scheduleSave()
    }

    private func scheduleSave() {
        let snapshot = PersistedState(version: PersistedState.currentVersion,
                                      folders: folders,
                                      labels: labels,
                                      ungroupedCollapsed: ungroupedCollapsed)
        let url = fileURL
        saveDebouncer.call {
            Self.writeAtomic(state: snapshot, to: url)
        }
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            Log.store.info("No state file at \(self.fileURL.path, privacy: .public), starting empty")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            self.labels = state.labels
            self.ungroupedCollapsed = state.ungroupedCollapsed
            // Drop label ids that no longer resolve (labels deleted out of band).
            let known = Set(state.labels.map(\.id))
            self.folders = state.folders.map { folder in
                var folder = folder
                folder.labelIDs = folder.labelIDs.filter { known.contains($0) }
                return folder
            }
            Log.store.info("Loaded \(state.folders.count) folders, \(state.labels.count) labels from disk")
        } catch {
            Log.store.error("Failed to load state: \(String(describing: error), privacy: .public)")
        }
    }

    private static func writeAtomic(state: PersistedState, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
            Log.store.debug("Saved state (\(data.count) bytes) to \(url.path, privacy: .public)")
        } catch {
            Log.store.error("Failed to save state: \(String(describing: error), privacy: .public)")
        }
    }
}
