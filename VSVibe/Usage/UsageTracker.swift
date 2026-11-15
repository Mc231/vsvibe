import Foundation

/// Watches the Claude transcript of a single pane (`TranscriptSource`) and
/// surfaces token usage. Polls every `pollInterval` for new JSONL lines, off
/// the main thread, parsing each assistant message's `usage` block to maintain
/// running totals + last context.
@MainActor
internal final class UsageTracker {
    private enum Constants {
        static let nanosecondsPerSecond = 1_000_000_000.0
        /// Delay before the first poll so a fresh pane doesn't race the CLI.
        static let initialDelayNanoseconds: UInt64 = 500_000_000
        /// Short pause between chunks while catching up on a large transcript.
        static let catchUpDelayNanoseconds: UInt64 = 10_000_000
    }

    internal let source: TranscriptSource
    private let pollInterval: TimeInterval = 1.5
    private let onUpdate: (SessionUsage) -> Void

    private var pollingTask: Task<Void, Never>?
    private var generation = UUID()

    internal init(source: TranscriptSource, onUpdate: @escaping (SessionUsage) -> Void) {
        self.source = source
        self.onUpdate = onUpdate
    }

    internal func start() {
        stop()
        let generation = generation
        let source = source
        let interval = UInt64(pollInterval * Constants.nanosecondsPerSecond)
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            var reader = TranscriptUsageReader(source: source)
            do {
                try await Task.sleep(nanoseconds: Constants.initialDelayNanoseconds)
                while !Task.isCancelled {
                    let update = reader.poll()
                    if let update {
                        await self?.publish(update, generation: generation)
                    }
                    // Catch up in bounded chunks without making the UI wait.
                    try await Task.sleep(
                        nanoseconds: reader.hasMoreData ? Constants.catchUpDelayNanoseconds : interval
                    )
                }
            } catch {
                // Cancellation ends polling.
            }
        }
    }

    internal func stop() {
        generation = UUID()
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func publish(_ usage: SessionUsage, generation: UUID) {
        guard self.generation == generation else {
            return
        }
        onUpdate(usage)
    }

    deinit { pollingTask?.cancel() }
}
