import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let folderStore: FolderStore
    let sessionManager: SessionManager
    let eventCoordinator: EventCoordinator
    let diskSpaceMonitor: DiskSpaceMonitor
    let statsStore: StatsStore
    var pendingEditor: ProjectEditorMode?
    var pendingLabelEditor: LabelEditorMode?
    var isManageLabelsPresented: Bool = false
    var isHookSetupPresented: Bool = false
    var pendingStats: FolderEntry?

    init() {
        let store = FolderStore()
        let stats = StatsStore()
        let manager = SessionManager(statsStore: stats)
        self.folderStore = store
        self.statsStore = stats
        self.sessionManager = manager
        self.eventCoordinator = EventCoordinator(folderStore: store, sessionManager: manager, statsStore: stats)
        self.diskSpaceMonitor = DiskSpaceMonitor()
    }

    func showStats(folder: FolderEntry) {
        pendingStats = folder
    }

    func dismissStats() {
        pendingStats = nil
    }

    func startEventStream() {
        eventCoordinator.start()
        diskSpaceMonitor.start()
    }

    func presentHookSetup() {
        isHookSetupPresented = true
    }

    /// Launch the "create project" flow: pick a path, then present the editor sheet.
    func beginCreateProjectFlow() {
        AddFolderCommand.run { [weak self] url in
            self?.pendingEditor = .create(url: url)
        }
    }

    func beginEditProjectFlow(folder: FolderEntry) {
        pendingEditor = .edit(folder: folder)
    }

    func cancelEditor() {
        pendingEditor = nil
    }

    func commitEditor(mode: ProjectEditorMode, result: ProjectEditorResult) {
        switch mode {
        case .create(let url):
            createProject(url: url,
                          name: result.name,
                          launchCommand: result.launchCommand,
                          openImmediately: result.openImmediately,
                          labelIDs: result.labelIDs)
        case .edit(let folder):
            updateProject(id: folder.id,
                          name: result.name,
                          launchCommand: result.launchCommand,
                          labelIDs: result.labelIDs)
        }
        pendingEditor = nil
    }

    // MARK: - Labels

    func beginCreateLabelFlow(assignTo folderID: FolderEntry.ID? = nil) {
        pendingLabelEditor = .create(assignTo: folderID)
    }

    func beginEditLabelFlow(_ label: ProjectLabel) {
        pendingLabelEditor = .edit(label: label)
    }

    func cancelLabelEditor() {
        pendingLabelEditor = nil
    }

    func commitLabelEditor(mode: LabelEditorMode, result: LabelEditorResult) {
        switch mode {
        case .create(let assignTo):
            let label = folderStore.createLabel(name: result.name,
                                                colorHex: result.colorHex,
                                                symbolName: result.symbolName)
            if let label, let folderID = assignTo {
                folderStore.addLabel(label.id, to: folderID)
            }
        case .edit(let label):
            folderStore.updateLabel(id: label.id,
                                    name: result.name,
                                    colorHex: result.colorHex,
                                    symbolName: result.symbolName)
        }
        pendingLabelEditor = nil
    }

    func presentManageLabels() {
        isManageLabelsPresented = true
    }

    /// Opens (or focuses) a pane for every project carrying `label`.
    func openAllPanes(inLabel labelID: ProjectLabel.ID) {
        for folder in folderStore.folders where folder.labelIDs.contains(labelID) {
            sessionManager.ensureSession(for: folder)
        }
    }

    /// Closes every pane belonging to projects carrying `label`.
    func closeAllPanes(inLabel labelID: ProjectLabel.ID) {
        for folder in folderStore.folders where folder.labelIDs.contains(labelID) {
            sessionManager.closeAllSessions(forFolder: folder.id)
        }
    }

    func bootstrapSessions() {
        for folder in folderStore.folders {
            sessionManager.ensureSession(for: folder)
        }
    }

    func addFolder(url: URL) {
        let alreadyKnown = folderStore.contains(url: url)
        folderStore.add(url: url)
        guard !alreadyKnown, let entry = folderStore.folders.last(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { return }
        sessionManager.ensureSession(for: entry)
    }

    /// Creates a new project (shortcut) with explicit name and launch command.
    /// Optionally opens its pane right away.
    @discardableResult
    func createProject(url: URL,
                       name: String,
                       launchCommand: String,
                       openImmediately: Bool,
                       labelIDs: [ProjectLabel.ID] = []) -> FolderEntry {
        let entry = folderStore.createProject(url: url,
                                              name: name,
                                              launchCommand: launchCommand,
                                              labelIDs: labelIDs)
        if openImmediately {
            sessionManager.ensureSession(for: entry)
        }
        return entry
    }

    /// Updates an existing project's name and/or launch command.
    /// If the launch command changes while a pane is running, restart the pane.
    func updateProject(id: FolderEntry.ID,
                       name: String,
                       launchCommand: String,
                       labelIDs: [ProjectLabel.ID]? = nil) {
        let previous = folderStore.folders.first(where: { $0.id == id })
        folderStore.updateProject(id: id, name: name, launchCommand: launchCommand, labelIDs: labelIDs)
        guard let prev = previous else { return }
        let commandChanged = prev.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            != launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if commandChanged, sessionManager.hasSession(forFolder: id),
           let updated = folderStore.folders.first(where: { $0.id == id }) {
            sessionManager.closeAllSessions(forFolder: id)
            sessionManager.ensureSession(for: updated)
        }
    }

    func removeFolderPermanently(id: FolderEntry.ID) {
        sessionManager.closeAllSessions(forFolder: id)
        folderStore.remove(id: id)
    }

    func setLaunchCommand(folderID: FolderEntry.ID, to command: String, restartIfRunning: Bool = true) {
        folderStore.setLaunchCommand(id: folderID, to: command)
        guard restartIfRunning,
              sessionManager.hasSession(forFolder: folderID),
              let updated = folderStore.folders.first(where: { $0.id == folderID })
        else { return }
        sessionManager.closeAllSessions(forFolder: folderID)
        sessionManager.ensureSession(for: updated)
    }

    func closePane(id: TerminalSession.ID) {
        sessionManager.closeSession(id: id)
    }

    func reopenPane(for folder: FolderEntry) {
        sessionManager.ensureSession(for: folder)
    }

    /// Open the pane if not yet running, or focus it if already running.
    func openOrFocus(folder: FolderEntry) {
        if let existing = sessionManager.firstSession(forFolder: folder.id) {
            sessionManager.focus(id: existing.id)
        } else {
            sessionManager.ensureSession(for: folder)
        }
    }

    /// Open a pane that resumes the folder's most recent session
    /// (`<launchCommand> --continue`), or focus the pane if one is already running.
    func continueOrFocus(folder: FolderEntry) {
        if let existing = sessionManager.firstSession(forFolder: folder.id) {
            sessionManager.focus(id: existing.id)
        } else {
            let command = LaunchCommandResolver.continueCommand(for: folder.launchCommand)
            sessionManager.ensureSession(for: folder, commandOverride: command)
        }
    }

    /// Spawn an additional pane for `folder` alongside any existing ones, so the
    /// new pane starts with a fresh process/context. The new pane takes focus.
    func openFreshPane(for folder: FolderEntry) {
        sessionManager.createSession(for: folder)
    }

    /// Variant used by pane chrome: open a fresh pane for the folder backing
    /// `sessionID` (which is itself left running).
    func openFreshPane(forSessionID sessionID: TerminalSession.ID) {
        guard let session = sessionManager.sessions.first(where: { $0.id == sessionID }) else { return }
        sessionManager.createSession(for: session.folder)
    }

    func openAllShortcuts() {
        for folder in folderStore.folders {
            sessionManager.ensureSession(for: folder)
        }
    }

    func closeAllPanes() {
        sessionManager.closeAllSessions()
    }

    /// Folder URL of the currently focused pane, if any.
    var focusedFolderURL: URL? {
        guard let id = sessionManager.focusedSessionID,
              let session = sessionManager.sessions.first(where: { $0.id == id })
        else { return nil }
        return session.folder.url
    }

    func openFocusedInEditor(_ editor: ExternalEditor) {
        guard let url = focusedFolderURL else { return }
        EditorRegistry.open(folder: url, with: editor)
    }
}
