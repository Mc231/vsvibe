import Foundation

/// One long-running ssh process (e.g. `tail -F` of a remote file) kept alive:
/// when it ends while the stream is running it is started again after the
/// `ReconnectBackoff` delay. `onConnect` runs before every (re)start, so the
/// consumer can reset its parsing state; output of an ended or stopped
/// process is ignored.
@MainActor
internal final class RemoteStream {
    private let arguments: [String]
    private let services: RemoteServices
    private let onConnect: () -> Void
    private let onOutput: (Data) -> Void

    private var process: (any RemoteProcessHandle)?
    private var generation = 0
    private var failures = 0
    private var connectedAt = Date.distantPast
    private var reconnectTask: Task<Void, Never>?

    /// Between `start()` and `stop()`, also while waiting to reconnect.
    internal private(set) var isRunning = false

    internal init(
        arguments: [String],
        services: RemoteServices,
        onConnect: @escaping () -> Void,
        onOutput: @escaping (Data) -> Void
    ) {
        self.arguments = arguments
        self.services = services
        self.onConnect = onConnect
        self.onOutput = onOutput
    }

    internal func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        failures = 0
        connect()
    }

    /// Terminates the process and cancels a pending reconnect.
    internal func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        process?.terminate()
        process = nil
    }

    private func connect() {
        generation += 1
        let current = generation
        connectedAt = services.now()
        onConnect()
        process = services.launcher.launch(
            arguments: arguments,
            onOutput: { [weak self] data in
                self?.received(data, generation: current)
            },
            onExit: { [weak self] in
                self?.ended(generation: current)
            }
        )
    }

    private func received(_ data: Data, generation: Int) {
        guard isRunning, generation == self.generation else {
            return
        }
        onOutput(data)
    }

    private func ended(generation: Int) {
        guard isRunning, generation == self.generation else {
            return
        }
        process = nil
        let connectedFor = services.now().timeIntervalSince(connectedAt)
        failures = services.backoff.failures(after: failures, connectedFor: connectedFor)
        let delay = services.backoff.delay(afterFailures: failures)
        let sleep = services.sleep
        reconnectTask = Task { [weak self] in
            await sleep(delay)
            self?.reconnect(generation: generation)
        }
    }

    private func reconnect(generation: Int) {
        guard isRunning, generation == self.generation else {
            return
        }
        reconnectTask = nil
        connect()
    }

    deinit {
        // Owners call stop(); the reconnect task holds only a weak reference.
    }
}
