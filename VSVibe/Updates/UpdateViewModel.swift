import Combine
import Dispatch
import Observation

/// Observable state behind the "Check for Updates…" menu item and the Updates
/// settings tab.
@MainActor
@Observable
internal final class UpdateViewModel {
    private enum InfoKey {
        static let shortVersion = "CFBundleShortVersionString"
        static let build = "CFBundleVersion"
    }

    internal private(set) var canCheckForUpdates = false
    internal private(set) var automaticallyChecksForUpdates: Bool
    internal private(set) var automaticallyDownloadsUpdates: Bool
    /// "Version 0.2.0 (123)".
    internal let versionDescription: String

    @ObservationIgnored private let updater: any AppUpdating
    @ObservationIgnored private var subscription: AnyCancellable?

    internal init(updater: any AppUpdating, infoDictionary: [String: Any]) {
        self.updater = updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        versionDescription = Self.versionDescription(infoDictionary: infoDictionary)
        subscription = updater.canCheckForUpdatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                // Delivered on the main queue (receive(on:) above).
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = canCheck
                }
            }
    }

    internal static func versionDescription(infoDictionary: [String: Any]) -> String {
        let version = infoDictionary[InfoKey.shortVersion] as? String ?? "?"
        let build = infoDictionary[InfoKey.build] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    internal func checkForUpdates() {
        guard canCheckForUpdates else {
            return
        }
        updater.checkForUpdates()
    }

    internal func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        // Sparkle derives automatic downloads from automatic checks.
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    internal func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updater.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    deinit {
        // The subscription cancels itself when released.
    }
}
