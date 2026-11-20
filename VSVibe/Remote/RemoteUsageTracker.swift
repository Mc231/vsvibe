import Foundation

/// Token usage of a remote pane: streams its Claude transcript (the remote
/// `transcript_path` its hook events reported) with
/// `tail -c +1 -F <path>` and feeds the bytes to a `UsageAccumulator`. Parsing
/// runs off the main actor, in order; each (re)connect re-reads the file from
/// the start into a fresh accumulator.
@MainActor
internal final class RemoteUsageTracker {
    private enum Input {
        case chunk(Data)
        case reset
    }

    internal let transcriptPath: String
    private let onUpdate: (SessionUsage) -> Void
    private let continuation: AsyncStream<Input>.Continuation
    private var parser: Task<Void, Never>?
    private var stream: RemoteStream?
    private var isStopped = false

    /// Starts streaming `transcriptPath` (validate it with `isValidPath` first).
    internal init(
        connection: SSHConnection,
        transcriptPath: String,
        services: RemoteServices,
        onUpdate: @escaping (SessionUsage) -> Void
    ) {
        self.transcriptPath = transcriptPath
        self.onUpdate = onUpdate
        let (inputs, continuation) = AsyncStream.makeStream(of: Input.self)
        self.continuation = continuation
        parser = Task.detached(priority: .utility) { [weak self] in
            var accumulator = UsageAccumulator()
            for await input in inputs {
                switch input {
                case .reset:
                    accumulator = UsageAccumulator()

                case .chunk(let data):
                    if let usage = accumulator.consume(data) {
                        await self?.publish(usage)
                    }
                }
            }
        }
        let stream = RemoteStream(
            arguments: RemoteSSH.streamArguments(for: connection, script: Self.script(for: transcriptPath)),
            services: services,
            onConnect: { continuation.yield(.reset) },
            onOutput: { continuation.yield(.chunk($0)) }
        )
        self.stream = stream
        stream.start()
    }

    /// The remote script streaming the whole transcript and following it.
    internal static func script(for transcriptPath: String) -> String {
        "exec tail -c +1 -F \(SSHCommand.shellQuoted(transcriptPath))"
    }

    /// Whether `path` may be streamed: absolute, a `.jsonl` file and free of
    /// control characters (it comes from the remote hook script).
    internal static func isValidPath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        return path.hasPrefix("/")
            && path.hasSuffix(".jsonl")
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// Stops the stream; nothing is published afterwards.
    internal func stop() {
        isStopped = true
        stream?.stop()
        stream = nil
        continuation.finish()
        parser?.cancel()
        parser = nil
    }

    private func publish(_ usage: SessionUsage) {
        if !isStopped {
            onUpdate(usage)
        }
    }

    deinit {
        parser?.cancel()
    }
}
