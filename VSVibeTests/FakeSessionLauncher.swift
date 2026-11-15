import Foundation
@testable import VSVibe

/// Builds a `SessionLauncher` that never spawns a process and records what the
/// manager asked for. Commands are reported missing unless listed in `onPath`
/// or `loginShellKnows`; commands in `loginShellTimesOut` are `.unknown`.
@MainActor
internal final class FakeSessionLauncher {
    internal private(set) var spawnedFolders: [URL] = []
    internal private(set) var spawnedPaneIDs: [UUID] = []
    internal var onPath: Set<String> = []
    internal let loginShellKnows: Set<String>
    internal let loginShellTimesOut: Set<String>

    internal var launcher: SessionLauncher {
        let known = loginShellKnows
        let unknown = loginShellTimesOut
        return SessionLauncher(
            makeTerminalView: SessionLauncher.makeTerminalView,
            spawnShell: { [weak self] _, folder, paneID in
                self?.spawnedFolders.append(folder)
                self?.spawnedPaneIDs.append(paneID)
            },
            isOnSearchPath: { [weak self] command in
                self?.onPath.contains(command) ?? false
            },
            loginShellAvailability: { command, _ in
                if known.contains(command) {
                    return .found
                }
                return unknown.contains(command) ? .unknown : .missing
            },
            commandDelay: 0
        )
    }

    internal init(loginShellKnows: Set<String> = [], loginShellTimesOut: Set<String> = []) {
        self.loginShellKnows = loginShellKnows
        self.loginShellTimesOut = loginShellTimesOut
    }

    deinit {
        // Test double; nothing to release.
    }
}
