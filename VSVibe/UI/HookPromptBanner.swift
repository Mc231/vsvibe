import SwiftUI

/// Dismissible banner at the top of the main window asking to install or
/// update the Claude hooks (see `HookPromptController`).
internal struct HookPromptBanner: View {
    private enum Layout {
        static let spacing: CGFloat = 10
        static let textSpacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let backgroundOpacity: Double = 0.14
    }

    internal let controller: HookPromptController

    private var isPrompting: Bool {
        if case .prompting = controller.state {
            return true
        }
        return false
    }

    private var installTitle: String {
        controller.state == .prompting(.outdated) ? "Update Hooks" : "Install Hooks"
    }

    internal var body: some View {
        HStack(spacing: Layout.spacing) {
            Image(systemName: controller.state == .installed ? "checkmark.circle.fill" : "bell.badge.fill")
                .foregroundStyle(controller.state == .installed ? Color.green : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                Text(controller.title).font(.callout.weight(.semibold))
                Text(controller.message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isPrompting {
                Button("Don't Ask Again") { controller.dontAskAgain() }
                    .buttonStyle(.borderless)
                Button("Not Now") { controller.dismiss() }
                Button(installTitle) { controller.installHooks() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("OK") { controller.dismiss() }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Color.accentColor.opacity(Layout.backgroundOpacity))
    }
}
