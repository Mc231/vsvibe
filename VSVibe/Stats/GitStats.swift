import Foundation

/// On-demand git metrics. Commit/churn figures cover a trailing window; the rest
/// are current snapshots.
internal struct GitStats {
    internal var isRepo: Bool = false
    internal var currentBranch: String?
    internal var branchCount: Int = 0
    internal var commitsInWindow: Int = 0
    internal var linesAdded: Int = 0
    internal var linesRemoved: Int = 0
    internal var filesTouched: Int = 0
    internal var ahead: Int?
    internal var behind: Int?
    internal var lastCommitDate: Date?
    internal var lastCommitSubject: String?
    internal var windowDays: Int = 30
}
