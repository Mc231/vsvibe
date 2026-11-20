import Foundation

/// One hook-event stream per remote host with open panes: ssh runs
/// `tail -n 0 -F ~/.vsvibe/events.jsonl` there (the file the stock hook script
/// appends to), and every complete line is decoded as a `HookEvent` and handed
/// to `onEvent` on the main actor. Events written while a stream is down are
/// not replayed (`tail -n 0`).
@MainActor
internal final class RemoteEventStreams {
    /// The remote script: make sure the file exists, then follow new lines
    /// (`-F` survives the file being replaced).
    internal static let script = "mkdir -p ~/.vsvibe && touch ~/.vsvibe/events.jsonl "
        + "&& exec tail -n 0 -F ~/.vsvibe/events.jsonl"

    private let services: RemoteServices
    private var streams: [SSHConnection: RemoteStream] = [:]
    private var splitters: [SSHConnection: LineSplitter] = [:]

    /// Receives every decoded remote event.
    internal var onEvent: (HookEvent) -> Void = { _ in
        // Set by the owner.
    }

    /// The hosts currently streamed.
    internal var connections: Set<SSHConnection> {
        Set(streams.keys)
    }

    internal init(services: RemoteServices) {
        self.services = services
    }

    /// Streams exactly `wanted`: starts the missing hosts, stops the others.
    internal func update(_ wanted: Set<SSHConnection>) {
        for connection in connections.subtracting(wanted) {
            streams.removeValue(forKey: connection)?.stop()
            splitters[connection] = nil
        }
        for connection in wanted.subtracting(connections) {
            let stream = RemoteStream(
                arguments: RemoteSSH.streamArguments(for: connection, script: Self.script),
                services: services,
                onConnect: { [weak self] in
                    self?.splitters[connection] = LineSplitter()
                },
                onOutput: { [weak self] data in
                    self?.received(data, from: connection)
                }
            )
            streams[connection] = stream
            stream.start()
        }
    }

    internal func stopAll() {
        update([])
    }

    private func received(_ data: Data, from connection: SSHConnection) {
        guard var splitter = splitters[connection] else {
            return
        }
        let lines = splitter.append(data)
        splitters[connection] = splitter
        for line in lines {
            if let event = HookEvent.decoded(fromLine: line) {
                onEvent(event)
            }
        }
    }

    deinit {
        // Streams are stopped explicitly via stopAll().
    }
}
