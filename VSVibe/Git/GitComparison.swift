internal struct GitComparison: Sendable {
    internal let baseCommit: String
    internal let targetCommit: String
    internal let files: [GitChangedFile]
}
