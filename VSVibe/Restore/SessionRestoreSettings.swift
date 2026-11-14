import Foundation

/// The "Restore sessions on launch" preference (UserDefaults, on by default).
/// The settings UI binds the same key through `@AppStorage`.
internal struct SessionRestoreSettings {
    internal static let key = "restoreSessionsOnLaunch"
    internal static let defaultValue = true

    private let defaults: UserDefaults

    /// Whether panes are saved while the app runs and reopened on launch.
    internal var isEnabled: Bool {
        defaults.object(forKey: Self.key) as? Bool ?? Self.defaultValue
    }

    internal init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
