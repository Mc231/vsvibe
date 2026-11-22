import AppKit
import SwiftTerm

/// A pane's terminal. Programs that track the mouse (Claude Code does) get every
/// click and drag, so plain dragging never selects text. Like iTerm, holding
/// Option while clicking/dragging selects text anyway; a right-click shows
/// Copy / Paste / Select All.
///
/// SwiftTerm clears the selection on every new output while mouse reporting is
/// on, and its mouse handlers can't be overridden. So a local event monitor turns
/// reporting off at an Option-click (or Select All), before the view sees it,
/// and keeps it off while that selection exists: output (Claude redraws all the
/// time, over ssh too) no longer wipes it before ⌘C. The next plain click or
/// keystroke in the pane drops the selection and gives the mouse back.
internal final class PaneTerminalView: LocalProcessTerminalView {
    /// True while a selection made over mouse tracking is held: reporting is off.
    internal private(set) var isHoldingSelection = false
    private var eventMonitor: Any?

    override internal func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard window != nil else {
            return
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown {
                    self?.handleKeyEvent(event)
                } else {
                    self?.handleMouseEvent(event)
                }
            }
            return event
        }
    }

    /// Called for every left mouse-down/up in the app, before it is dispatched.
    internal func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard isInside(event) else {
                return
            }
            if event.modifierFlags.contains(.option) {
                holdSelection()
            } else if isHoldingSelection {
                // The click goes to the program again; the old selection goes away.
                releaseSelection()
            }

        case .leftMouseUp:
            guard isHoldingSelection else {
                return
            }
            // An Option-click without a drag selects nothing: give the mouse back
            // once the view has handled this mouse-up.
            DispatchQueue.main.async { [weak self] in
                guard let self, !selectionActive else {
                    return
                }
                releaseSelection()
            }

        default:
            return
        }
    }

    /// Called for every key-down in the app, before it is dispatched.
    internal func handleKeyEvent(_ event: NSEvent) {
        guard event.window === window, window?.firstResponder === self else {
            return
        }
        if event.modifierFlags.contains(.command) {
            // ⌘C keeps the selection; ⌘A (Edit → Select All) makes one to hold.
            if event.charactersIgnoringModifiers == "a" {
                holdSelection()
            }
            return
        }
        if isHoldingSelection {
            releaseSelection()
        }
    }

    @objc
    internal func selectAllText(_ sender: Any?) {
        holdSelection()
        selectAll(sender)
    }

    override internal func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(selectAllText(_:)) || super.validateUserInterfaceItem(item)
    }

    override internal func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Terminal")
        menu.addItem(item("Copy", #selector(copy(_:))))
        menu.addItem(item("Paste", #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(selectAllText(_:))))
        return menu
    }

    private func isInside(_ event: NSEvent) -> Bool {
        event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    private func holdSelection() {
        isHoldingSelection = true
        allowMouseReporting = false
    }

    private func releaseSelection() {
        isHoldingSelection = false
        allowMouseReporting = true
        selectNone()
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
