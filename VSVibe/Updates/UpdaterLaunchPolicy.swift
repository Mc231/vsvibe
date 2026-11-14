/// Whether the updater should start its scheduled checks in this process.
internal enum UpdaterLaunchPolicy {
    /// Set by Xcode when the app is the host of a unit-test bundle.
    private static let testConfigurationKey = "XCTestConfigurationFilePath"

    /// `false` while hosting unit tests, so a test run never checks for updates.
    internal static func shouldStartUpdater(environment: [String: String]) -> Bool {
        environment[testConfigurationKey] == nil
    }
}
