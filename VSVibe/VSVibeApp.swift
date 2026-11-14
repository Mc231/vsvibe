import SwiftUI

@main
internal struct VSVibeApp: App {
    private enum Layout {
        static let minWindowWidth: CGFloat = 900
        static let minWindowHeight: CGFloat = 600
    }

    @State private var env = AppEnvironment()
    // SwiftUI installs the delegate by reflection; the analyzer can't see that.
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate // swiftlint:disable:this unused_declaration

    internal var body: some Scene {
        WindowGroup("VSVibe") {
            RootSplitView()
                .environment(env)
                .frame(minWidth: Layout.minWindowWidth, minHeight: Layout.minWindowHeight)
                .task {
                    env.startEventStream()
                }
                .sheet(
                    isPresented: Binding(
                        get: { env.isHookSetupPresented },
                        set: { env.isHookSetupPresented = $0 }
                    )
                ) {
                    HookSetupView(aliasStore: env.aliasStore) { env.isHookSetupPresented = false }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Hide the default "New Window" item.
            }
            fileCommands
            CommandGroup(after: .appSettings) {
                Button("Aliases & Claude Hooks…") {
                    env.presentHookSetup()
                }
            }
            openInCommands
            CommandGroup(replacing: .help) {
                // No help book.
            }
        }

        Settings {
            SettingsView()
        }
    }

    @CommandsBuilder private var fileCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Project…") {
                env.beginCreateProjectFlow()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Open All Shortcuts") {
                env.openAllShortcuts()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Close All Panes") {
                env.closeAllPanes()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }

    @CommandsBuilder private var openInCommands: some Commands {
        CommandMenu("Open In") {
            ForEach(EditorRegistry.availableEditors()) { editor in
                Button {
                    env.openFocusedInEditor(editor)
                } label: {
                    Label(editor.displayName, systemImage: editor.iconSystemName)
                }
                .modifier(OptionalShortcut(key: editor.shortcutKey, modifiers: editor.shortcutModifiers))
                .disabled(env.focusedFolderURL == nil)
            }
            if EditorRegistry.availableEditors().isEmpty {
                Text("No supported editors detected")
            }
        }
    }

    internal init() {
        // Don't let macOS restore stale windows that would duplicate panes.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }
}
