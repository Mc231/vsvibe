import SwiftUI

internal struct GridContainerView: View {
    private enum Layout {
        static let gridPadding: CGFloat = 8
    }

    @Environment(AppEnvironment.self)
    private var env

    internal var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            if env.sessionManager.sessions.isEmpty {
                EmptyStateView()
            } else {
                TilingGridView(sessions: env.sessionManager.sessions) { session in
                    PaneView(session: session)
                }
                .padding(Layout.gridPadding)
                .animation(nil, value: env.sessionManager.sessions.count)
            }
        }
    }
}
