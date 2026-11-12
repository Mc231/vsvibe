import Foundation
import Observation

/// Periodically samples free vs. total capacity of the root volume so the
/// toolbar can show it next to the app title.
@MainActor
@Observable
internal final class DiskSpaceMonitor {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.includesUnit = true
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    internal private(set) var availableBytes: Int64 = 0
    internal private(set) var totalBytes: Int64 = 0

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let pollInterval: TimeInterval = 15

    internal var availableLabel: String { Self.formatter.string(fromByteCount: availableBytes) }
    internal var totalLabel: String { Self.formatter.string(fromByteCount: totalBytes) }

    internal init() {
        refresh()
    }

    internal func start() {
        stop()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        source.setEventHandler { [weak self] in self?.refresh() }
        timer = source
        source.resume()
    }

    internal func stop() {
        timer?.cancel()
        timer = nil
    }

    internal func refresh() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return
        }
        if let available = values.volumeAvailableCapacityForImportantUsage {
            availableBytes = available
        }
        if let total = values.volumeTotalCapacity {
            totalBytes = Int64(total)
        }
    }

    deinit {
        // The timer source is cancelled by `stop()`; nothing else to release.
    }
}
