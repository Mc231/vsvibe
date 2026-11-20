import Foundation

/// Polls a remote pane's git branch over ssh (one short call per interval on
/// the host's multiplexed connection, off the main thread) and reports
/// changes: the branch name, the short commit for a detached HEAD, or nil when
/// the folder is not a repository or the host can't be reached.
@MainActor
internal final class RemoteBranchTracker {
    private static let maxBranchLength = 255

    private let arguments: [String]
    private let services: RemoteServices
    private let onUpdate: (String?) -> Void
    private var task: Task<Void, Never>?
    private var lastBranch: String?
    private var didReport = false

    internal var isRunning: Bool {
        task != nil
    }

    internal init(
        connection: SSHConnection,
        remotePath: String,
        services: RemoteServices,
        onUpdate: @escaping (String?) -> Void
    ) {
        self.arguments = RemoteSSH.commandArguments(for: connection, script: Self.script(for: remotePath))
        self.services = services
        self.onUpdate = onUpdate
    }

    /// The remote script printing the branch of `remotePath` (the remote home
    /// when empty; a leading `~` expands remotely, see `SSHCommand`).
    internal static func script(for remotePath: String) -> String {
        let folder = SSHCommand.quotedRemotePath(remotePath.isEmpty ? "~" : remotePath)
        return "cd \(folder) 2>/dev/null && "
            + "{ git symbolic-ref --short -q HEAD || git rev-parse --short HEAD; } 2>/dev/null"
    }

    /// The branch in a call's result: the first line of a successful call's
    /// output when it is a plausible ref name, else nil.
    internal static func branch(from result: RemoteCommandResult) -> String? {
        guard result.status == 0 else {
            return nil
        }
        let line = result.outputText
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty,
            line.count <= maxBranchLength,
            !line.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        return line
    }

    internal func start() {
        guard task == nil else {
            return
        }
        let arguments = arguments
        let runner = services.runner
        let sleep = services.sleep
        let interval = services.branchPollInterval
        task = Task { [weak self] in
            while !Task.isCancelled {
                let result = await runner.run(arguments: arguments, input: nil)
                guard !Task.isCancelled else {
                    return
                }
                self?.report(Self.branch(from: result))
                await sleep(interval)
            }
        }
    }

    internal func stop() {
        task?.cancel()
        task = nil
    }

    /// Reports `branch` when it differs from the last report (the first
    /// result is always reported).
    private func report(_ branch: String?) {
        guard !didReport || branch != lastBranch else {
            return
        }
        didReport = true
        lastBranch = branch
        onUpdate(branch)
    }

    deinit {
        task?.cancel()
    }
}
