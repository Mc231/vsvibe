import SwiftUI

internal struct RootSplitView: View {
    private enum Layout {
        static let sidebarMinWidth: CGFloat = 200
        static let sidebarIdealWidth: CGFloat = 240
        static let sidebarMaxWidth: CGFloat = 320
    }

    @Environment(AppEnvironment.self)
    private var env
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    internal var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Layout.sidebarMinWidth,
                    ideal: Layout.sidebarIdealWidth,
                    max: Layout.sidebarMaxWidth
                )
        } detail: {
            GridContainerView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if env.hookPrompt.isVisible {
                        HookPromptBanner(controller: env.hookPrompt)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            MainToolbar()
        }
        .sheet(item: Binding(get: { env.pendingStats }, set: { env.pendingStats = $0 })) { folder in
            ProjectStatsView(folder: folder) { env.dismissStats() }
        }
        .sheet(item: Binding(get: { env.pendingGitReview }, set: { env.pendingGitReview = $0 })) { folder in
            GitReviewView(folder: folder)
        }
    }
}
