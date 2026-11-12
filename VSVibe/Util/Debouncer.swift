import Foundation

@MainActor
internal final class Debouncer {
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    internal init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Schedules `action` after `interval`, replacing any pending action.
    internal func call(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            // Work items scheduled on the main queue run on the main actor.
            MainActor.assumeIsolated {
                self?.workItem = nil
            }
            action()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    /// Runs the pending action now (if any) instead of waiting for the interval.
    internal func flush() {
        guard let item = workItem else {
            return
        }
        workItem = nil
        // `perform()` is a no-op on a cancelled item, so run first, then cancel
        // the scheduled copy so the action does not fire a second time.
        item.perform()
        item.cancel()
    }

    deinit {
        // Nothing to release: a pending work item is owned by the main queue.
    }
}
