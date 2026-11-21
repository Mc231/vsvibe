import AppKit
import Foundation
import SwiftTerm

/// The process-facing side effects `SessionManager` performs when it opens a
/// pane. `live` drives SwiftTerm and the real PATH / login shell; tests inject
/// stand-ins so sessions can be created without spawning shells.
@MainActor
internal struct SessionLauncher {
    private enum Constants {
        /// Delay before typing the launch command, so the shell has initialized.
        /// Fixed delay is reliable enough; first PTY paint usually happens within ~150ms.
        static let commandDelay: TimeInterval = 0.45
        static let initialWidth: CGFloat = 800
        static let initialHeight: CGFloat = 600
    }

    /// SwiftTerm, the user's PATH and login shell.
    internal static let live = Self(
        makeTerminalView: Self.makeTerminalView,
        spawnShell: Self.spawnShell,
        typeCommand: Self.typeCommand,
        isOnSearchPath: Self.isOnSearchPath,
        loginShellAvailability: { command, shell in
            CommandLocator.loginShellAvailability(command, shell: shell)
        },
        commandDelay: Constants.commandDelay
    )

    /// Creates the (not yet started) terminal view for a new pane.
    internal var makeTerminalView: () -> LocalProcessTerminalView
    /// Starts the login shell in `folder` inside the view; the pane id is
    /// exported to the shell as `VSVIBE_PANE_ID`.
    internal var spawnShell: (LocalProcessTerminalView, URL, UUID) -> Void
    /// Types a command line (plus return) into the pane's shell.
    internal var typeCommand: (LocalProcessTerminalView, String) -> Void
    /// Fast PATH probe for a bare executable name.
    internal var isOnSearchPath: (String) -> Bool
    /// Authoritative (slow, timeout-bounded) check via the interactive login
    /// shell: `(command, shell)`.
    internal var loginShellAvailability: @Sendable (String, String) -> CommandAvailability
    /// Seconds to wait before typing the launch command into the new shell.
    internal var commandDelay: TimeInterval

    internal static func makeTerminalView() -> LocalProcessTerminalView {
        let frame = NSRect(x: 0, y: 0, width: Constants.initialWidth, height: Constants.initialHeight)
        let view = PaneTerminalView(frame: frame)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    internal static func spawnShell(in view: LocalProcessTerminalView, at folder: URL, paneID: UUID) {
        view.spawnShell(at: folder, paneID: paneID)
    }

    internal static func typeCommand(in view: LocalProcessTerminalView, command: String) {
        view.injectCommand(command)
    }

    internal static func isOnSearchPath(_ command: String) -> Bool {
        CommandLocator.resolveExecutable(command, searchPaths: EnvBuilder.searchPaths()) != nil
    }
}
