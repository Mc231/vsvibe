import Foundation

/// Display formatting for the stats sheet.
internal enum Format {
    private enum Unit {
        static let costWholeDollarThreshold: Double = 100
        static let million = 1_000_000
        static let thousand = 1_000
        static let secondsPerHour = 3_600
        static let secondsPerMinute = 60
    }

    private static let claudePrefix = "claude-"

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    internal static func cost(_ usd: Double) -> String {
        if usd >= Unit.costWholeDollarThreshold {
            return String(format: "$%.0f", usd)
        }
        return String(format: "$%.2f", usd)
    }

    internal static func tokens(_ count: Int) -> String {
        if count >= Unit.million {
            return String(format: "%.1fM", Double(count) / Double(Unit.million))
        }
        if count >= Unit.thousand {
            return String(format: "%.0fk", Double(count) / Double(Unit.thousand))
        }
        return "\(count)"
    }

    internal static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / Unit.secondsPerHour
        let minutes = (total % Unit.secondsPerHour) / Unit.secondsPerMinute
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(total)s"
    }

    internal static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// `claude-opus-4-7` → `Opus 4.7`.
    internal static func model(_ raw: String) -> String {
        var trimmed = raw
        if trimmed.hasPrefix(claudePrefix) {
            trimmed = String(trimmed.dropFirst(claudePrefix.count))
        }
        let parts = trimmed.split(separator: "-")
        guard let family = parts.first else {
            return raw
        }
        let version = parts.dropFirst().joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
