import Foundation
@testable import VSVibe

/// Builds a `SessionLauncher` that never spawns a process and records what the
/// manager asked for. Commands are reported missing unless listed in `onPath`
/// or `loginShellKnows`.
@MainActor
internal final class FakeSessionLauncher {
    internal private(set) var spawnedFolders: [URL] = []
    internal private(set) var spawnedPaneIDs: [UUID] = []
    internal var onPath: Set<String> = []
    internal let loginShellKnows: Set<String>

    internal var launcher: SessionLauncher {
        let known = loginShellKnows
        return SessionLauncher(
            makeTerminalView: SessionLauncher.makeTerminalView,
            spawnShell: { [weak self] _, folder, paneID in
                self?.spawnedFolders.append(folder)
                self?.spawnedPaneIDs.append(paneID)
            },
            isOnSearchPath: { [weak self] command in
                self?.onPath.contains(command) ?? false
            },
            loginShellCanFind: { command, _ in
                known.contains(command)
            },
            commandDelay: 0
        )
    }

    internal init(loginShellKnows: Set<String> = []) {
        self.loginShellKnows = loginShellKnows
    }

    deinit {
        // Test double; nothing to release.
    }
}
