import Foundation

/// A thread-safe queue of canned answers for fake remote calls.
internal final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [String]

    internal init(_ answers: [String]) {
        remaining = answers
    }

    /// The next answer, nil once all were used.
    internal func next() -> String? {
        lock.withLock {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }

    deinit {
        // Test double; nothing to release.
    }
}
