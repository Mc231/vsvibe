import Foundation

/// A user-created label ("folder") used to group project shortcuts in the
/// sidebar. A project may carry several labels and therefore appear under
/// several sections.
internal struct ProjectLabel: Codable, Identifiable, Hashable {
    private enum CodingKeys: CodingKey {
        case colorHex
        case createdAt
        case id
        case isCollapsed
        case name
        case symbolName
    }

    internal let id: UUID
    internal var name: String
    /// `#RRGGBB` — see `ColorHex`.
    internal var colorHex: String
    /// SF Symbol name shown in the section header.
    internal var symbolName: String
    /// Whether the sidebar section is collapsed (persisted across launches).
    internal var isCollapsed: Bool
    internal let createdAt: Date

    internal init(
        name: String,
        colorHex: String = LabelPalette.defaultColor,
        symbolName: String = LabelPalette.defaultSymbol,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.colorHex = ColorHex.normalized(colorHex) ?? LabelPalette.defaultColor
        self.symbolName = symbolName.isEmpty ? LabelPalette.defaultSymbol : symbolName
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let hex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        self.colorHex = hex.flatMap(ColorHex.normalized) ?? LabelPalette.defaultColor
        let symbol = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? ""
        self.symbolName = symbol.isEmpty ? LabelPalette.defaultSymbol : symbol
        self.isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// Applies an edit from the label editor. A blank name or symbol and an
    /// invalid color leave the current value in place.
    internal mutating func applyEdit(name newName: String, colorHex newColor: String, symbolName newSymbol: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            name = trimmed
        }
        if let hex = ColorHex.normalized(newColor) {
            colorHex = hex
        }
        if !newSymbol.isEmpty {
            symbolName = newSymbol
        }
    }
}
