import SwiftUI
import AppKit

@main
struct VSVibeApp: App {
    @State private var env = AppEnvironment()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Don't let macOS restore stale windows that would duplicate panes.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    var body: some Scene {
        WindowGroup("VSVibe") {
            RootSplitView()
                .environment(env)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    env.startEventStream()
                }
                .sheet(isPresented: Binding(
                    get: { env.isHookSetupPresented },
                    set: { env.isHookSetupPresented = $0 })
                ) {
                    HookSetupView(onClose: { env.isHookSetupPresented = false })
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
            CommandGroup(after: .appSettings) {
                Button("Setup Claude Hooks…") {
                    env.presentHookSetup()
                }
            }
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
            CommandGroup(replacing: .help) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: String?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key, let char = key.first {
            content.keyboardShortcut(KeyEquivalent(char), modifiers: modifiers)
        } else {
            content
        }
    }
}
