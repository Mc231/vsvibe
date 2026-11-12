import AppKit

@MainActor
internal final class AppDelegate: NSObject, NSApplicationDelegate {
    internal func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    deinit {
        // Owned by the app for its whole lifetime; nothing to tear down.
    }
}
