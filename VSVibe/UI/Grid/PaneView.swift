import SwiftUI

struct PaneView: View {
    @Environment(AppEnvironment.self) private var env
    let session: TerminalSession

    @State private var isFocused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PaneChromeView(
                session: session,
                onClose: { env.closePane(id: session.id) },
                onRestart: { env.sessionManager.reload(id: session.id) },
                onOpenFreshPane: { env.openFreshPane(forSessionID: session.id) },
                onShowStats: { env.showStats(folder: session.folder) }
            )
            if let warning = session.errorMessage {
                PaneWarningBanner(
                    message: warning,
                    onEditProject: { env.beginEditProjectFlow(folder: session.folder) },
                    onDismiss: { session.errorMessage = nil }
                )
            }
            TerminalHostView(terminalView: session.terminalView) { focused in
                isFocused = focused
                if focused {
                    env.sessionManager.focusedSessionID = session.id
                    env.eventCoordinator.clearUnread(for: session.id)
                }
            }
        }
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(2)
    }
}

private struct PaneWarningBanner: View {
    let message: String
    let onEditProject: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Edit Project…", action: onEditProject)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.yellow)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.14))
    }
}
