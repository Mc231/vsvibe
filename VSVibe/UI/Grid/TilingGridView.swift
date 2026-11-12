import SwiftUI

internal struct TilingGridView<Content: View>: View {
    internal let sessions: [TerminalSession]
    @ViewBuilder internal let content: (TerminalSession) -> Content

    internal var body: some View {
        TileLayout {
            ForEach(sessions) { session in
                content(session)
            }
        }
    }
}
