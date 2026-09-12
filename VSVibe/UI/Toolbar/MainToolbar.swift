import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(AppEnvironment.self) private var env

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DiskSpaceLabel(monitor: env.diskSpaceMonitor)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                env.beginCreateProjectFlow()
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .help("New Project (⇧⌘O)")
        }
    }
}

private struct DiskSpaceLabel: View {
    let monitor: DiskSpaceMonitor

    private var usedFraction: Double {
        guard monitor.totalBytes > 0 else { return 0 }
        let used = max(0, monitor.totalBytes - monitor.availableBytes)
        return min(1, Double(used) / Double(monitor.totalBytes))
    }

    private var tint: Color {
        switch usedFraction {
        case 0..<0.75: return .secondary
        case 0.75..<0.9: return .yellow
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(monitor.availableLabel) / \(monitor.totalLabel)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .help("Free / total space on the root volume.")
        .onTapGesture { monitor.refresh() }
    }
}
