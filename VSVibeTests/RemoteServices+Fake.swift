@testable import VSVibe

@MainActor
internal extension RemoteServices {
    /// Fake ssh, and a `sleep` that only yields (reconnects and polls run at once).
    static func fake(
        launcher: FakeProcessLauncher,
        runner: FakeRemoteRunner = FakeRemoteRunner { _, _ in RemoteCommandResult(status: 1) }
    ) -> Self {
        var services = Self(runner: runner, launcher: launcher)
        services.sleep = { _ in await Task.yield() }
        return services
    }
}
