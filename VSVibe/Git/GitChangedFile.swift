internal struct GitChangedFile: Identifiable, Equatable, Sendable {
    internal let path: String
    internal let status: String
    internal let added: Int?
    internal let removed: Int?

    internal var id: String { path }
    internal var isBinary: Bool { added == nil || removed == nil }
}
