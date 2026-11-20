import Foundation
@testable import VSVibe

/// `RemoteShellRunning` stand-in: answers each call with `respond(script,
/// input)` and records the calls. `script` is the remote script unwrapped from
/// `exec /bin/sh -c '…'`.
internal final class FakeRemoteRunner: RemoteShellRunning, @unchecked Sendable {
    internal struct Call: Equatable {
        internal let arguments: [String]
        internal let script: String
        internal let input: Data?
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let respond: @Sendable (String, Data?) -> RemoteCommandResult

    internal var calls: [Call] {
        lock.withLock { recorded }
    }

    internal init(respond: @escaping @Sendable (String, Data?) -> RemoteCommandResult) {
        self.respond = respond
    }

    /// The script inside the `exec /bin/sh -c '<script>'` last argument.
    internal static func innerScript(of arguments: [String]) -> String {
        let prefix = "exec /bin/sh -c '"
        guard let last = arguments.last, last.hasPrefix(prefix), last.hasSuffix("'") else {
            return arguments.last ?? ""
        }
        return String(last.dropFirst(prefix.count).dropLast()).replacingOccurrences(of: #"'\''"#, with: "'")
    }

    internal func run(arguments: [String], input: Data?) async -> RemoteCommandResult {
        await Task.yield()
        let script = Self.innerScript(of: arguments)
        lock.withLock {
            recorded.append(Call(arguments: arguments, script: script, input: input))
        }
        return respond(script, input)
    }

    deinit {
        // Test double; nothing to release.
    }
}
