import Combine
@testable import VSVibe

/// In-memory `AppUpdating` that mimics Sparkle: automatic downloads read as
/// off while automatic checks are off.
@MainActor
internal final class FakeUpdater: AppUpdating {
    private let canCheck = CurrentValueSubject<Bool, Never>(false)
    internal private(set) var checkCount = 0
    internal var automaticallyChecksForUpdates = true
    private var storedDownloads = false

    internal var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        canCheck.eraseToAnyPublisher()
    }

    internal var automaticallyDownloadsUpdates: Bool {
        get { automaticallyChecksForUpdates && storedDownloads }
        set { storedDownloads = newValue }
    }

    internal func setCanCheck(_ value: Bool) {
        canCheck.send(value)
    }

    internal func checkForUpdates() {
        checkCount += 1
    }

    deinit {
        // Nothing to release.
    }
}
