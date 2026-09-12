import Foundation
import Observation

/// Periodically samples free vs. total capacity of the root volume so the
/// toolbar can show it next to the app title.
@MainActor
@Observable
final class DiskSpaceMonitor {
    private(set) var availableBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let pollInterval: TimeInterval = 15

    init() {
        refresh()
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.refresh() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        if let available = values.volumeAvailableCapacityForImportantUsage {
            availableBytes = available
        }
        if let total = values.volumeTotalCapacity {
            totalBytes = Int64(total)
        }
    }

    var availableLabel: String { Self.formatter.string(fromByteCount: availableBytes) }
    var totalLabel: String { Self.formatter.string(fromByteCount: totalBytes) }

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useTB]
        f.includesUnit = true
        f.zeroPadsFractionDigits = false
        return f
    }()
}
