import Combine
import Sparkle

/// `AppUpdating` backed by Sparkle's standard updater and update UI.
///
/// Glue only (excluded from coverage): the relaunch decision lives in the
/// tested `RelaunchGuard`, the start decision in `UpdaterLaunchPolicy`.
@MainActor
internal final class SparkleUpdater: AppUpdating {
    private let relaunchHandler: SparkleUpdaterDelegate
    private let controller: SPUStandardUpdaterController

    internal var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    internal var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    internal var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// - Parameter lostSessionCount: running sessions a relaunch would close.
    internal init(lostSessionCount: @escaping @MainActor () -> Int) {
        // Sparkle holds its delegate weakly; this object keeps it alive.
        relaunchHandler = SparkleUpdaterDelegate(relaunchGuard: RelaunchGuard(lostSessionCount: lostSessionCount))
        controller = SPUStandardUpdaterController(
            startingUpdater: UpdaterLaunchPolicy.shouldStartUpdater(
                environment: ProcessInfo.processInfo.environment
            ),
            updaterDelegate: relaunchHandler,
            userDriverDelegate: nil
        )
    }

    internal func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    deinit {
        // Lives for the whole app run; Sparkle tears itself down on quit.
    }
}
