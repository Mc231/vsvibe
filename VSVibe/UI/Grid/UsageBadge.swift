import SwiftUI

/// Compact capsule in the pane chrome showing context usage, total tokens and cost.
internal struct UsageBadge: View {
    private enum Layout {
        static let spacing: CGFloat = 6
        static let innerSpacing: CGFloat = 2
        static let iconSize: CGFloat = 9
        static let fontSize: CGFloat = 10
        static let tokensOpacity: Double = 0.8
        static let costOpacity: Double = 0.6
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2
        static let backgroundOpacity: Double = 0.08
    }

    private enum Threshold {
        static let contextWarning: Double = 60
        static let contextCritical: Double = 85
        static let minimumCostUSD: Double = 0.01
        static let million: Double = 1_000_000
        static let thousand: Double = 1_000
    }

    internal let usage: SessionUsage

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            HStack(spacing: Layout.innerSpacing) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .accessibilityHidden(true)
                Text(String(format: "%.0f%%", usage.contextPercent))
                    .font(.system(size: Layout.fontSize, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(pctColor)

            Text(totalTokensLabel)
                .font(.system(size: Layout.fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(Layout.tokensOpacity))

            if usage.estimatedCostUSD >= Threshold.minimumCostUSD {
                Text(String(format: "$%.2f", usage.estimatedCostUSD))
                    .font(.system(size: Layout.fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(Layout.costOpacity))
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(Color.white.opacity(Layout.backgroundOpacity)))
        .help(helpText)
    }

    private var pctColor: Color {
        switch usage.contextPercent {
        case 0..<Threshold.contextWarning:
            return .green

        case Threshold.contextWarning..<Threshold.contextCritical:
            return .yellow

        default:
            return .red
        }
    }

    private var totalTokensLabel: String {
        let total = usage.totalInput + usage.totalOutput + usage.totalCacheCreation + usage.totalCacheRead
        let value = Double(total)
        if value >= Threshold.million {
            return String(format: "%.1fM", value / Threshold.million)
        }
        if value >= Threshold.thousand {
            return String(format: "%.0fk", value / Threshold.thousand)
        }
        return "\(total)"
    }

    private var helpText: String {
        "Context \(Int(usage.contextPercent))% of \(usage.contextWindow.formatted()) · \(usage.messageCount) msgs"
    }
}
