import SwiftUI

extension Color {
    /// Builds a color from a persisted `#RRGGBB` label color, falling back to
    /// the accent color when the string is unusable.
    init(labelHex hex: String) {
        guard let rgb = ColorHex.rgb(from: hex) else {
            self = .accentColor
            return
        }
        self = Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension ProjectLabel {
    var color: Color { Color(labelHex: colorHex) }
}
