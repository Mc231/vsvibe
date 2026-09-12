import Foundation

@MainActor
final class Debouncer {
    private let interval: TimeInterval
    private var workItem: DispatchWorkItem?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func call(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func flush() {
        workItem?.cancel()
        let item = workItem
        workItem = nil
        item?.perform()
    }
}
