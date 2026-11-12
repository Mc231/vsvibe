internal enum GitComparisonMode: String, CaseIterable, Identifiable, Sendable {
    case mergeBase = "Since common ancestor"
    case tips = "Branch tips"

    internal var id: Self { self }
}
