import Foundation

/// Starts long-running ssh streams (`SSHStreamLauncher`; tests use a fake).
@MainActor
internal protocol RemoteProcessLaunching {
    /// Starts ssh with `arguments` (see `RemoteSSH.streamArguments`). Its stdout
    /// is delivered in order to `onOutput` on the main actor; `onExit` runs
    /// once when it ends (also when it could not start).
    func launch(
        arguments: [String],
        onOutput: @escaping @MainActor (Data) -> Void,
        onExit: @escaping @MainActor () -> Void
    ) -> any RemoteProcessHandle
}
