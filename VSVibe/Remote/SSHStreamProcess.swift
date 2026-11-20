import Foundation

/// A stream process started by `SSHStreamLauncher`: drops output once
/// terminated and reports its exit once.
@MainActor
internal final class SSHStreamProcess: RemoteProcessHandle {
    private let process: Process
    private let reader: FileHandle
    private var isTerminated = false
    private var didExit = false

    internal init(process: Process, reader: FileHandle) {
        self.process = process
        self.reader = reader
    }

    internal func terminate() {
        isTerminated = true
        reader.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    /// Hands `data` to `onOutput` unless the process was terminated.
    internal func deliver(_ data: Data, to onOutput: @MainActor (Data) -> Void) {
        if !isTerminated {
            onOutput(data)
        }
    }

    /// Reports the exit (once) and stops reading. The pipe closes when the
    /// handle is released (closing it here could race a read in progress).
    internal func finish(_ onExit: @MainActor () -> Void) {
        guard !didExit else {
            return
        }
        didExit = true
        reader.readabilityHandler = nil
        process.terminationHandler = nil
        onExit()
    }

    deinit {
        // The process is terminated via terminate(); the pipe closes on release.
    }
}
