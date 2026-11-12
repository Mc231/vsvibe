import SwiftUI

struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            GridContainerView()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            MainToolbar()
        }
        .sheet(item: Binding(get: { env.pendingStats }, set: { env.pendingStats = $0 })) { folder in
            ProjectStatsView(folder: folder, onClose: { env.dismissStats() })
        }
        .sheet(item: Binding(get: { env.pendingGitReview }, set: { env.pendingGitReview = $0 })) { folder in
            GitReviewView(folder: folder)
        }
    }
}

struct GridContainerView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            if env.sessionManager.sessions.isEmpty {
                EmptyStateView()
            } else {
                TilingGridView(sessions: env.sessionManager.sessions) { session in
                    PaneView(session: session)
                }
                .padding(8)
                .animation(nil, value: env.sessionManager.sessions.count)
            }
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppEnvironment.self) private var env

    private var hasShortcuts: Bool { !env.folderStore.folders.isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasShortcuts ? "play.rectangle.on.rectangle" : "square.grid.2x2")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(hasShortcuts ? "No panes open" : "No shortcuts yet")
                .font(.title2)
                .fontWeight(.medium)
            Text(hasShortcuts
                 ? "Click a shortcut in the sidebar to open it."
                 : "Add a folder to create a shortcut.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    env.beginCreateProjectFlow()
                } label: {
                    Label("New Project", systemImage: "plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: [.command, .shift])
                if hasShortcuts {
                    Button {
                        env.openAllShortcuts()
                    } label: {
                        Label("Open All", systemImage: "play.fill")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                }
            }
        }
        .padding(40)
    }
}
