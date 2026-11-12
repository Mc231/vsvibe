/// Fixed choices offered by the label editor. Keeping them fixed means labels
/// always look at home in the sidebar and stay legible in both appearances.
internal enum LabelPalette {
    internal static let colors: [String] = [
        "#3B82F6", // blue
        "#8B5CF6", // purple
        "#EC4899", // pink
        "#EF4444", // red
        "#F97316", // orange
        "#EAB308", // yellow
        "#22C55E", // green
        "#14B8A6", // teal
        "#64748B" // slate
    ]

    internal static let symbols: [String] = [
        "folder.fill",
        "briefcase.fill",
        "hammer.fill",
        "flask.fill",
        "leaf.fill",
        "bolt.fill",
        "star.fill",
        "heart.fill",
        "cube.fill",
        "server.rack",
        "globe",
        "gamecontroller.fill"
    ]

    internal static let defaultColor = "#3B82F6"
    internal static let defaultSymbol = "folder.fill"

    /// Picks the next unused palette color, cycling once they are all taken.
    internal static func suggestedColor(usedBy existing: [ProjectLabel]) -> String {
        let used = Set(existing.map(\.colorHex))
        return colors.first { !used.contains($0) } ?? colors[existing.count % colors.count]
    }
}
