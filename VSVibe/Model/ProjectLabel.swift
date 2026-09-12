import Foundation

/// A user-created label ("folder") used to group project shortcuts in the
/// sidebar. A project may carry several labels and therefore appear under
/// several sections.
struct ProjectLabel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// `#RRGGBB` — see `ColorHex`.
    var colorHex: String
    /// SF Symbol name shown in the section header.
    var symbolName: String
    /// Whether the sidebar section is collapsed (persisted across launches).
    var isCollapsed: Bool
    let createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = LabelPalette.defaultColor,
         symbolName: String = LabelPalette.defaultSymbol,
         isCollapsed: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = ColorHex.normalized(colorHex) ?? LabelPalette.defaultColor
        self.symbolName = symbolName.isEmpty ? LabelPalette.defaultSymbol : symbolName
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, symbolName, isCollapsed, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        let hex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        self.colorHex = hex.flatMap(ColorHex.normalized) ?? LabelPalette.defaultColor
        let symbol = try c.decodeIfPresent(String.self, forKey: .symbolName) ?? ""
        self.symbolName = symbol.isEmpty ? LabelPalette.defaultSymbol : symbol
        self.isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Fixed choices offered by the label editor. Keeping them fixed means labels
/// always look at home in the sidebar and stay legible in both appearances.
enum LabelPalette {
    static let colors: [String] = [
        "#3B82F6", // blue
        "#8B5CF6", // purple
        "#EC4899", // pink
        "#EF4444", // red
        "#F97316", // orange
        "#EAB308", // yellow
        "#22C55E", // green
        "#14B8A6", // teal
        "#64748B"  // slate
    ]

    static let symbols: [String] = [
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

    static let defaultColor = "#3B82F6"
    static let defaultSymbol = "folder.fill"

    /// Picks the next unused palette color, cycling once they are all taken.
    static func suggestedColor(usedBy existing: [ProjectLabel]) -> String {
        let used = Set(existing.map(\.colorHex))
        return colors.first { !used.contains($0) } ?? colors[existing.count % colors.count]
    }
}
