import AppKit
import SwiftTerm

/// A pane's terminal. Programs that track the mouse (Claude Code does) get every
/// click and drag, so plain dragging never selects text. Like iTerm, holding
/// Option while clicking/dragging selects text anyway; a right-click shows
/// Copy / Paste / Select All.
///
/// SwiftTerm's mouse handlers can't be overridden, so a local event monitor turns
/// mouse reporting off for an Option-click before the view sees it and back on
/// once its mouse-up has been handled.
internal final class PaneTerminalView: LocalProcessTerminalView {
    /// True from an Option-mouse-down until its mouse-up: mouse reporting is off.
    internal private(set) var isSelectingOverMouseTracking = false
    private var mouseMonitor: Any?

    override internal func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        guard window != nil else {
            return
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseEvent(event)
            }
            return event
        }
    }

    /// Called for every left mouse-down/up in the app, before it is dispatched.
    internal func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let isOptionClickHere = event.modifierFlags.contains(.option) && event.window === window
                && bounds.contains(convert(event.locationInWindow, from: nil))
            guard isOptionClickHere else {
                return
            }
            isSelectingOverMouseTracking = true
            allowMouseReporting = false

        case .leftMouseUp:
            guard isSelectingOverMouseTracking else {
                return
            }
            // The view handles this mouse-up after the monitor returns.
            DispatchQueue.main.async { [weak self] in
                self?.isSelectingOverMouseTracking = false
                self?.allowMouseReporting = true
            }

        default:
            return
        }
    }

    override internal func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Terminal")
        menu.addItem(item("Copy", #selector(copy(_:))))
        menu.addItem(item("Paste", #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(selectAll(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    deinit {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }
}
