import Foundation

/// Parsing/formatting for the `#RRGGBB` strings used to persist label colors.
/// Pure Foundation so it stays unit-testable; the SwiftUI bridge lives in
/// `UI/LabelColor.swift`.
internal enum ColorHex {
    internal struct RGB: Equatable {
        internal var red: Double
        internal var green: Double
        internal var blue: Double
    }

    private enum Constants {
        static let longLength = 6
        static let shortLength = 3
        static let radix = 16
        static let redShift: UInt32 = 16
        static let greenShift: UInt32 = 8
        static let channelMask: UInt32 = 0xFF
        static let channelMax = 255.0
    }

    /// Accepts `RGB`, `RRGGBB`, with or without a leading `#`, any case.
    /// Returns nil for anything else.
    internal static func rgb(from hex: String) -> RGB? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == Constants.longLength || digits.count == Constants.shortLength else {
            return nil
        }
        guard digits.allSatisfy(\.isHexDigit) else {
            return nil
        }
        if digits.count == Constants.shortLength {
            // Expand shorthand: #abc -> #aabbcc
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(digits, radix: Constants.radix) else {
            return nil
        }
        return RGB(
            red: channel(value >> Constants.redShift),
            green: channel(value >> Constants.greenShift),
            blue: channel(value)
        )
    }

    /// Canonical `#RRGGBB` uppercase form, or nil when `hex` is not a color.
    internal static func normalized(_ hex: String) -> String? {
        guard let rgb = rgb(from: hex) else {
            return nil
        }
        let red = Int((rgb.red * Constants.channelMax).rounded())
        let green = Int((rgb.green * Constants.channelMax).rounded())
        let blue = Int((rgb.blue * Constants.channelMax).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func channel(_ shifted: UInt32) -> Double {
        Double(shifted & Constants.channelMask) / Constants.channelMax
    }
}
