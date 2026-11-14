/// Decides whether installing an update may relaunch the app right away.
///
/// Relaunching closes every terminal pane. When running sessions would be lost
/// (session restore off), the user confirms first; declining postpones the
/// relaunch and the update installs when the app quits.
@MainActor
internal struct RelaunchGuard {
    /// What to ask the user before relaunching.
    internal struct Prompt: Equatable {
        internal let title: String
        internal let message: String
        internal let confirmTitle: String
        internal let cancelTitle: String
    }

    private let lostSessionCount: @MainActor () -> Int

    /// - Parameter lostSessionCount: number of running sessions a relaunch would close.
    internal init(lostSessionCount: @escaping @MainActor () -> Int) {
        self.lostSessionCount = lostSessionCount
    }

    /// The confirmation to show, or `nil` when nothing would be lost.
    internal func prompt() -> Prompt? {
        let lost = lostSessionCount()
        guard lost > 0 else {
            return nil
        }
        let sessions = lost == 1 ? "1 session is" : "\(lost) sessions are"
        return Prompt(
            title: "Install the update and relaunch VSVibe?",
            message: "\(sessions) running and will be closed. "
                + "Choose Later to install the update when you quit VSVibe.",
            confirmTitle: "Install and Relaunch",
            cancelTitle: "Later"
        )
    }

    /// `true` to postpone the relaunch: sessions would be lost and `confirm`
    /// (shown the prompt) returned `false`.
    internal func shouldPostponeRelaunch(confirm: (Prompt) -> Bool) -> Bool {
        guard let prompt = prompt() else {
            return false
        }
        return !confirm(prompt)
    }
}
