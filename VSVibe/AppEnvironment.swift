import Foundation
import Observation

@MainActor
@Observable
internal final class AppEnvironment {
    internal let aliasStore: LaunchAliasStore
    internal let folderStore: FolderStore
    internal let sessionManager: SessionManager
    internal let eventCoordinator: EventCoordinator
    internal let diskSpaceMonitor: DiskSpaceMonitor
    internal let statsStore: StatsStore
    internal let sessionRestore: SessionRestoreController
    /// Launch prompt to install / update the Claude hooks.
    internal let hookPrompt: HookPromptController
    internal var pendingEditor: ProjectEditorMode?
    internal var pendingLabelEditor: LabelEditorMode?
    internal var isManageLabelsPresented: Bool = false
    internal var isHookSetupPresented: Bool = false
    internal var pendingStats: FolderEntry?
    internal var pendingGitReview: FolderEntry?

    /// Folder URL of the currently focused pane, if any.
    internal var focusedFolderURL: URL? {
        guard
            let id = sessionManager.focusedSessionID,
            let session = sessionManager.sessions.first(where: { $0.id == id })
        else {
            return nil
        }
        return session.folder.url
    }

    internal init() {
        let store = FolderStore()
        let aliases = LaunchAliasStore()
        self.aliasStore = aliases
        let stats = StatsStore { aliases.aliases }
        let manager = SessionManager(statsStore: stats, aliasStore: aliases)
        self.folderStore = store
        self.statsStore = stats
        self.sessionManager = manager
        self.eventCoordinator = EventCoordinator(folderStore: store, sessionManager: manager, statsStore: stats)
        self.diskSpaceMonitor = DiskSpaceMonitor()
        self.sessionRestore = SessionRestoreController(
            sessionManager: manager,
            folderStore: store,
            lookups: SessionRestorePlan.Lookups(
                aliasForCommand: { aliases.alias(for: $0) },
                aliasForConfigDir: { aliases.alias(forConfigDir: $0) },
                fileExists: { FileManager.default.fileExists(atPath: $0) }
            )
        )
        self.hookPrompt = HookPromptController(
            status: { HookInstaller.currentStatus(aliases: aliases.aliases) },
            install: { try HookInstaller.install(aliases: aliases.aliases) }
        )
    }

    internal func showStats(folder: FolderEntry) {
        pendingStats = folder
    }

    internal func dismissStats() {
        pendingStats = nil
    }

    internal func startEventStream() {
        eventCoordinator.start()
        diskSpaceMonitor.start()
        // Never touch the user's panes or sessions.json, or prompt, from the unit-test host.
        if !SessionRestoreController.isUnitTestHost(environment: ProcessInfo.processInfo.environment) {
            sessionRestore.start()
            hookPrompt.evaluateOnLaunch()
        }
    }

    internal func presentHookSetup() {
        isHookSetupPresented = true
    }

    /// Launch the "create project" flow: pick a path, then present the editor sheet.
    internal func beginCreateProjectFlow() {
        AddFolderCommand.run { [weak self] url in
            self?.pendingEditor = .create(url: url)
        }
    }

    internal func beginEditProjectFlow(folder: FolderEntry) {
        pendingEditor = .edit(folder: folder)
    }

    internal func cancelEditor() {
        pendingEditor = nil
    }

    internal func commitEditor(mode: ProjectEditorMode, result: ProjectEditorResult) {
        switch mode {
        case .create(let url):
            createProject(
                url: url,
                name: result.name,
                launchCommand: result.launchCommand,
                openImmediately: result.openImmediately,
                labelIDs: result.labelIDs
            )

        case .edit(let folder):
            updateProject(
                id: folder.id,
                name: result.name,
                launchCommand: result.launchCommand,
                labelIDs: result.labelIDs
            )
        }
        pendingEditor = nil
    }

    // MARK: - Labels

    internal func beginCreateLabelFlow(assignTo folderID: FolderEntry.ID? = nil) {
        pendingLabelEditor = .create(assignTo: folderID)
    }

    internal func beginEditLabelFlow(_ label: ProjectLabel) {
        pendingLabelEditor = .edit(label: label)
    }

    internal func cancelLabelEditor() {
        pendingLabelEditor = nil
    }

    internal func commitLabelEditor(mode: LabelEditorMode, result: LabelEditorResult) {
        switch mode {
        case .create(let assignTo):
            let label = folderStore.createLabel(
                name: result.name,
                colorHex: result.colorHex,
                symbolName: result.symbolName
            )
            if let label, let folderID = assignTo {
                folderStore.addLabel(label.id, to: folderID)
            }

        case .edit(let label):
            folderStore.updateLabel(
                id: label.id,
                name: result.name,
                colorHex: result.colorHex,
                symbolName: result.symbolName
            )
        }
        pendingLabelEditor = nil
    }

    internal func presentManageLabels() {
        isManageLabelsPresented = true
    }

    /// Opens (or focuses) a pane for every project carrying `label`.
    internal func openAllPanes(inLabel labelID: ProjectLabel.ID) {
        for folder in folderStore.folders where folder.labelIDs.contains(labelID) {
            sessionManager.ensureSession(for: folder)
        }
    }

    /// Closes every pane belonging to projects carrying `label`.
    internal func closeAllPanes(inLabel labelID: ProjectLabel.ID) {
        for folder in folderStore.folders where folder.labelIDs.contains(labelID) {
            sessionManager.closeAllSessions(forFolder: folder.id)
        }
    }

    /// Creates a new project (shortcut) with explicit name and launch command.
    /// Optionally opens its pane right away.
    @discardableResult
    internal func createProject(
        url: URL,
        name: String,
        launchCommand: String,
        openImmediately: Bool,
        labelIDs: [ProjectLabel.ID] = []
    ) -> FolderEntry {
        let entry = folderStore.createProject(
            url: url,
            name: name,
            launchCommand: launchCommand,
            labelIDs: labelIDs
        )
        if openImmediately {
            sessionManager.ensureSession(for: entry)
        }
        return entry
    }

    /// Updates an existing project's name, launch command and labels.
    /// If the launch command changes while a pane is running, restart the pane.
    internal func updateProject(
        id: FolderEntry.ID,
        name: String,
        launchCommand: String,
        labelIDs: [ProjectLabel.ID]
    ) {
        let previous = folderStore.folders.first { $0.id == id }
        folderStore.updateProject(id: id, name: name, launchCommand: launchCommand, labelIDs: labelIDs)
        guard let prev = previous else {
            return
        }
        let commandChanged = prev.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            != launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if commandChanged,
            sessionManager.hasSession(forFolder: id),
            let updated = folderStore.folders.first(where: { $0.id == id }) {
            sessionManager.closeAllSessions(forFolder: id)
            sessionManager.ensureSession(for: updated)
        }
    }

    internal func removeFolderPermanently(id: FolderEntry.ID) {
        sessionManager.closeAllSessions(forFolder: id)
        folderStore.remove(id: id)
    }

    internal func closePane(id: TerminalSession.ID) {
        sessionManager.closeSession(id: id)
    }

    internal func reopenPane(for folder: FolderEntry) {
        sessionManager.ensureSession(for: folder)
    }

    /// Open the pane if not yet running, or focus it if already running.
    internal func openOrFocus(folder: FolderEntry) {
        if let existing = sessionManager.firstSession(forFolder: folder.id) {
            sessionManager.focus(id: existing.id)
        } else {
            sessionManager.ensureSession(for: folder)
        }
    }

    /// Open a pane that resumes the folder's most recent session
    /// (`<launchCommand> --continue`), or focus the pane if one is already running.
    internal func continueOrFocus(folder: FolderEntry) {
        if let existing = sessionManager.firstSession(forFolder: folder.id) {
            sessionManager.focus(id: existing.id)
        } else {
            let command = LaunchCommandResolver.continueCommand(for: folder.launchCommand)
            sessionManager.ensureSession(for: folder, commandOverride: command)
        }
    }

    /// Variant used by pane chrome: open a fresh pane for the folder backing
    /// `sessionID` (which is itself left running).
    internal func openFreshPane(forSessionID sessionID: TerminalSession.ID) {
        guard let session = sessionManager.sessions.first(where: { $0.id == sessionID }) else {
            return
        }
        sessionManager.createSession(for: session.folder)
    }

    internal func openAllShortcuts() {
        for folder in folderStore.folders {
            sessionManager.ensureSession(for: folder)
        }
    }

    internal func closeAllPanes() {
        sessionManager.closeAllSessions()
    }

    internal func openFocusedInEditor(_ editor: ExternalEditor) {
        guard let url = focusedFolderURL else {
            return
        }
        EditorRegistry.open(folder: url, with: editor)
    }

    deinit {
        // Lives for the whole app lifetime; nothing to tear down.
    }
}
