import AppKit
import Foundation
import Observation

/// Reopens the panes of the previous run on launch and keeps `sessions.json`
/// current while the app runs: a debounced save whenever the panes, their
/// Claude session ids or the focus change (so a crash loses at most the last
/// debounce interval), plus a final save when the app terminates.
///
/// With "Restore sessions on launch" off nothing is reopened and the file is
/// removed instead of written.
@MainActor
internal final class SessionRestoreController {
    private enum Constants {
        static let saveDelay: TimeInterval = 1
        /// Set by XCTest in the test host process.
        static let testConfigurationKey = "XCTestConfigurationFilePath"
    }

    private let sessionManager: SessionManager
    private let folderStore: FolderStore
    private let lookups: SessionRestorePlan.Lookups
    private let settings: SessionRestoreSettings
    private let fileURL: URL
    private let notificationCenter: NotificationCenter
    private let saveDebouncer: Debouncer
    private var terminationObserver: (any NSObjectProtocol)?

    /// Whether `start()` has run (it only acts once per app run).
    internal private(set) var isStarted = false

    internal init(
        sessionManager: SessionManager,
        folderStore: FolderStore,
        lookups: SessionRestorePlan.Lookups,
        settings: SessionRestoreSettings = SessionRestoreSettings(),
        fileURL: URL = AppPaths.sessionsFile,
        saveDelay: TimeInterval = Constants.saveDelay,
        notificationCenter: NotificationCenter = .default
    ) {
        self.sessionManager = sessionManager
        self.folderStore = folderStore
        self.lookups = lookups
        self.settings = settings
        self.fileURL = fileURL
        self.notificationCenter = notificationCenter
        self.saveDebouncer = Debouncer(interval: saveDelay)
    }

    /// True inside the unit-test host, where restoring would spawn the user's
    /// real panes and saving would overwrite their `sessions.json`.
    internal static func isUnitTestHost(environment: [String: String]) -> Bool {
        environment[Constants.testConfigurationKey] != nil
    }

    /// Explains the panes that did not resume the way their project command would.
    private static func log(_ pane: SessionRestorePlan.Pane) {
        let folder = pane.folder.locationDescription
        switch pane.resolution {
        case .transcriptMissing:
            Log.session.info("Not resuming in \(folder, privacy: .public): the conversation's transcript is gone")

        case .resumedWithUnknownConfigDir(let configDir):
            let dir = configDir?.path ?? "none"
            Log.session.info(
                "No alias uses Claude config dir \(dir, privacy: .public); resuming with the project command"
            )

        case .resumedWithOwningAlias(let command):
            Log.session.info("Resuming in \(folder, privacy: .public) with alias \(command, privacy: .public)")

        case .resumedRemote:
            Log.session.info("Resuming the remote conversation in \(folder, privacy: .public)")

        case .launchCommand, .resumedWithProjectCommand:
            break
        }
    }

    /// Restores the previous panes (when enabled), then starts saving on every
    /// change and on termination. Later calls do nothing.
    internal func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        if settings.isEnabled {
            restore()
        }
        observeSessions()
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.save()
            }
        }
        scheduleSave()
    }

    /// Stops observing termination (pane changes stop being saved once the
    /// controller is released).
    internal func stop() {
        if let terminationObserver {
            notificationCenter.removeObserver(terminationObserver)
        }
        terminationObserver = nil
    }

    /// Writes the current panes now (or removes the file when restore is off).
    internal func save() {
        guard settings.isEnabled else {
            SessionSnapshotFile.remove(at: fileURL)
            return
        }
        SessionSnapshotFile.write(sessionManager.snapshot, to: fileURL)
    }

    private func restore() {
        guard let snapshot = SessionSnapshotFile.read(from: fileURL) else {
            return
        }
        let plan = SessionRestorePlan.make(snapshot: snapshot, folders: folderStore.folders, lookups: lookups)
        let restored = plan.panes.map { pane in
            Self.log(pane)
            return sessionManager.restoreSession(
                for: pane.folder,
                command: pane.command,
                claudeSessionID: pane.claudeSessionID,
                transcriptPath: pane.transcriptPath
            )
        }
        if let index = plan.focusedIndex {
            sessionManager.focus(id: restored[index].id)
        }
        Log.session.info("Restored \(restored.count) of \(snapshot.panes.count) panes")
    }

    private func scheduleSave() {
        saveDebouncer.call { [weak self] in
            self?.save()
        }
    }

    /// Re-arms itself after every change: observation fires only once.
    private func observeSessions() {
        withObservationTracking {
            _ = sessionManager.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleSave()
                self?.observeSessions()
            }
        }
    }

    deinit {
        // The termination observer is removed in stop(); its block holds self weakly.
    }
}
