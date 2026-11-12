import SwiftUI

/// Toolbar capsule showing free / total space on the root volume.
/// Tapping it refreshes the reading.
internal struct DiskSpaceLabel: View {
    private enum Layout {
        static let spacing: CGFloat = 5
        static let fontSize: CGFloat = 11
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 3
        static let backgroundOpacity: Double = 0.12
    }

    private enum Threshold {
        static let warning: Double = 0.75
        static let critical: Double = 0.9
    }

    internal let monitor: DiskSpaceMonitor

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            Image(systemName: "internaldrive")
                .font(.system(size: Layout.fontSize, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(monitor.availableLabel) / \(monitor.totalLabel)")
                .font(.system(size: Layout.fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(Color.secondary.opacity(Layout.backgroundOpacity)))
        .help("Free / total space on the root volume.")
        .onTapGesture { monitor.refresh() }
        .accessibilityAddTraits(.isButton)
    }

    private var usedFraction: Double {
        guard monitor.totalBytes > 0 else {
            return 0
        }
        let used = max(0, monitor.totalBytes - monitor.availableBytes)
        return min(1, Double(used) / Double(monitor.totalBytes))
    }

    private var tint: Color {
        switch usedFraction {
        case 0..<Threshold.warning:
            return .secondary

        case Threshold.warning..<Threshold.critical:
            return .yellow

        default:
            return .red
        }
    }
}
