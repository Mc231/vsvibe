import Foundation

/// Parsing/formatting for the `#RRGGBB` strings used to persist label colors.
/// Pure Foundation so it stays unit-testable; the SwiftUI bridge lives in
/// `UI/LabelColor.swift`.
enum ColorHex {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Accepts `RGB`, `RRGGBB`, with or without a leading `#`, any case.
    /// Returns nil for anything else.
    static func rgb(from hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 3 else { return nil }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        if s.count == 3 {
            // Expand shorthand: #abc -> #aabbcc
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(s, radix: 16) else { return nil }
        return RGB(red: Double((value >> 16) & 0xFF) / 255.0,
                   green: Double((value >> 8) & 0xFF) / 255.0,
                   blue: Double(value & 0xFF) / 255.0)
    }

    /// Canonical `#RRGGBB` uppercase form, or nil when `hex` is not a color.
    static func normalized(_ hex: String) -> String? {
        guard let rgb = rgb(from: hex) else { return nil }
        let r = Int((rgb.red * 255).rounded())
        let g = Int((rgb.green * 255).rounded())
        let b = Int((rgb.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
