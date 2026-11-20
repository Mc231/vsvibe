import Foundation

/// `RemoteProcessLaunching` with a real process: runs `executableURL` (ssh)
/// with an argv array (no local shell); stdout is a pipe read as data arrives
/// and handed to the main queue in order. The exit is reported from the
/// termination handler, not the pipe's end, so a multiplexing master forked
/// by ssh can't delay it.
@MainActor
internal struct SSHStreamLauncher: RemoteProcessLaunching {
    internal let executableURL: URL
    /// Prepared (`RemoteSSH.prepareControlDirectory`) before each launch; nil skips it.
    internal let controlDirectory: URL?

    internal init(
        executableURL: URL = RemoteSSH.executableURL,
        controlDirectory: URL? = RemoteSSH.controlDirectory
    ) {
        self.executableURL = executableURL
        self.controlDirectory = controlDirectory
    }

    internal func launch(
        arguments: [String],
        onOutput: @escaping @MainActor (Data) -> Void,
        onExit: @escaping @MainActor () -> Void
    ) -> any RemoteProcessHandle {
        if let controlDirectory {
            try? RemoteSSH.prepareControlDirectory(at: controlDirectory)
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        let handle = SSHStreamProcess(process: process, reader: pipe.fileHandleForReading)
        pipe.fileHandleForReading.readabilityHandler = { reader in
            let data = reader.availableData
            guard !data.isEmpty else {
                reader.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handle.deliver(data, to: onOutput)
                }
            }
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handle.finish(onExit)
                }
            }
        }
        do {
            try process.run()
        } catch {
            Log.app.error("Could not start \(executableURL.path, privacy: .public)")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    handle.finish(onExit)
                }
            }
        }
        return handle
    }
}
