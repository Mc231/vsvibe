import SwiftUI

internal struct PaneView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 6
        static let idleBorderOpacity: Double = 0.08
        static let focusedBorderWidth: CGFloat = 2
        static let idleBorderWidth: CGFloat = 1
        static let outerPadding: CGFloat = 2
    }

    @Environment(AppEnvironment.self)
    private var env
    internal let session: TerminalSession

    @State private var isFocused: Bool = false

    internal var body: some View {
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
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color.white.opacity(Layout.idleBorderOpacity),
                    lineWidth: isFocused ? Layout.focusedBorderWidth : Layout.idleBorderWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
        .padding(Layout.outerPadding)
    }
}
