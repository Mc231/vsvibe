import Foundation

/// Polls a folder's git `HEAD` for the current branch and reports changes.
/// Mirrors the polling style of `UsageTracker`; reading `HEAD` is a tiny file
/// read, so re-checking on a short interval is effectively free and reflects
/// `git checkout` live.
@MainActor
internal final class GitBranchTracker {
    /// Reads the current branch for a folder (nil when detached / not a repo).
    internal typealias BranchReader = (URL) -> String?

    /// How often `HEAD` is re-read while running.
    internal nonisolated static let defaultPollInterval: TimeInterval = 2.0

    private let folderURL: URL
    private let pollInterval: TimeInterval
    private let branchReader: BranchReader
    private let onUpdate: (String?) -> Void

    private var timer: DispatchSourceTimer?
    private var lastBranch: String?
    private var didReport = false

    /// True while the poll timer is scheduled.
    internal var isRunning: Bool { timer != nil }

    internal init(
        folderURL: URL,
        pollInterval: TimeInterval = defaultPollInterval,
        branchReader: @escaping BranchReader = { GitInfo.currentBranch(forFolder: $0) },
        onUpdate: @escaping (String?) -> Void
    ) {
        self.folderURL = folderURL
        self.pollInterval = pollInterval
        self.branchReader = branchReader
        self.onUpdate = onUpdate
    }

    internal func start() {
        stop()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: pollInterval)
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    internal func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One poll: reads the branch and reports it when it differs from the last
    /// reported value (the first read is always reported, even when nil).
    internal func tick() {
        let branch = branchReader(folderURL)
        guard !didReport || branch != lastBranch else {
            return
        }
        didReport = true
        lastBranch = branch
        onUpdate(branch)
    }

    deinit {
        // The timer handler holds only a weak reference; `stop()` cancels it.
    }
}
