import Foundation
@testable import VSVibe

/// `HookEventNotifying` stand-in that records posts instead of showing them.
@MainActor
internal final class RecordingNotifier: HookEventNotifying {
    internal struct Post: Equatable {
        internal let title: String
        internal let body: String
        internal let sessionID: UUID?
    }

    internal private(set) var posts: [Post] = []
    internal private(set) var activationHandler: ((UUID) -> Void)?

    internal func configure(onActivateSession: @escaping (UUID) -> Void) {
        activationHandler = onActivateSession
    }

    internal func post(title: String, body: String, sessionID: UUID?) {
        posts.append(Post(title: title, body: body, sessionID: sessionID))
    }

    deinit {
        // Test double; nothing to release.
    }
}
