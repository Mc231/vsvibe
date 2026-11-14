import AppKit
import Sparkle

/// Sparkle delegate: asks before a relaunch that would close running sessions
/// (decision in the tested `RelaunchGuard`). Glue only, excluded from coverage.
@MainActor
internal final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let relaunchGuard: RelaunchGuard

    internal init(relaunchGuard: RelaunchGuard) {
        self.relaunchGuard = relaunchGuard
    }

    internal func updater(
        _: SPUUpdater,
        shouldPostponeRelaunchForUpdate _: SUAppcastItem,
        untilInvokingBlock _: @escaping () -> Void
    ) -> Bool {
        relaunchGuard.shouldPostponeRelaunch { prompt in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = prompt.title
            alert.informativeText = prompt.message
            alert.addButton(withTitle: prompt.confirmTitle)
            alert.addButton(withTitle: prompt.cancelTitle)
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    deinit {
        // Owned by SparkleUpdater; nothing to release.
    }
}
