import Foundation

/// Polls a folder's git `HEAD` for the current branch and reports changes.
/// Mirrors the polling style of `UsageTracker`; reading `HEAD` is a tiny file
/// read, so re-checking on a short interval is effectively free and reflects
/// `git checkout` live.
@MainActor
final class GitBranchTracker {
    private let folderURL: URL
    private let pollInterval: TimeInterval = 2.0
    private let onUpdate: (String?) -> Void

    private var timer: DispatchSourceTimer?
    private var lastBranch: String?
    private var didReport = false

    init(folderURL: URL, onUpdate: @escaping (String?) -> Void) {
        self.folderURL = folderURL
        self.onUpdate = onUpdate
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let branch = GitInfo.currentBranch(forFolder: folderURL)
        guard !didReport || branch != lastBranch else { return }
        didReport = true
        lastBranch = branch
        onUpdate(branch)
    }
}
