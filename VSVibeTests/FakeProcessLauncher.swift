import Foundation
@testable import VSVibe

/// `RemoteProcessLaunching` stand-in: records every launch; tests make a
/// launched "process" print output or exit.
@MainActor
internal final class FakeProcessLauncher: RemoteProcessLaunching {
    /// One launched stream process.
    internal final class Launch: RemoteProcessHandle {
        internal let arguments: [String]
        internal private(set) var isTerminated = false
        private let onOutput: @MainActor (Data) -> Void
        private let onExit: @MainActor () -> Void

        /// The remote script (the last argument, unwrapped from `exec /bin/sh -c '…'`).
        internal var script: String {
            FakeRemoteRunner.innerScript(of: arguments)
        }

        internal init(
            arguments: [String],
            onOutput: @escaping @MainActor (Data) -> Void,
            onExit: @escaping @MainActor () -> Void
        ) {
            self.arguments = arguments
            self.onOutput = onOutput
            self.onExit = onExit
        }

        internal func emit(_ text: String) {
            onOutput(Data(text.utf8))
        }

        internal func exit() {
            onExit()
        }

        internal func terminate() {
            isTerminated = true
        }

        deinit {
            // Test double; nothing to release.
        }
    }

    internal private(set) var launches: [Launch] = []

    /// Launches not terminated by their owner.
    internal var running: [Launch] {
        launches.filter { !$0.isTerminated }
    }

    internal func launch(
        arguments: [String],
        onOutput: @escaping @MainActor (Data) -> Void,
        onExit: @escaping @MainActor () -> Void
    ) -> any RemoteProcessHandle {
        let launch = Launch(arguments: arguments, onOutput: onOutput, onExit: onExit)
        launches.append(launch)
        return launch
    }

    deinit {
        // Test double; nothing to release.
    }
}
