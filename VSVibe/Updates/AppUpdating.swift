import Combine

/// The app's view of the auto-updater (Sparkle in the app, a fake in tests).
@MainActor
internal protocol AppUpdating: AnyObject {
    /// Emits whether a user-initiated check is possible right now (current value first).
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }

    /// Starts a user-initiated check that shows Sparkle's standard update UI.
    func checkForUpdates()
}
