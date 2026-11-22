import AppKit
@testable import VSVibe
import XCTest

/// Selecting and copying text while a program (Claude Code) tracks the mouse.
@MainActor
internal final class PaneTerminalViewTests: XCTestCase {
    private func makeView() -> PaneTerminalView {
        PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        option: Bool,
        at location: NSPoint = NSPoint(x: 10, y: 10)
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: option ? [.option] : [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    internal func testTheLauncherMakesPaneTerminalViews() {
        XCTAssertTrue(SessionLauncher.makeTerminalView() is PaneTerminalView)
    }

    private func keyEvent(_ characters: String, command: Bool = false, window: NSWindow? = nil) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: command ? [.command] : [],
                timestamp: 0,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 0
            )
        )
    }

    internal func testAnOptionDragSelectionSurvivesOutputUntilThePlainClick() async throws {
        let view = makeView()
        view.feed(text: "line one\r\n")

        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: true))
        view.selectAll(nil)
        view.handleMouseEvent(try mouseEvent(.leftMouseUp, option: false))
        await AsyncWait.drainMainQueue()
        view.feed(text: "Claude redraws\r\nmore output\r\n")
        await AsyncWait.drainMainQueue()

        XCTAssertFalse(view.allowMouseReporting)
        XCTAssertTrue(view.isHoldingSelection)
        XCTAssertTrue(view.selectionActive, "new output must not wipe the selection")

        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: false))
        XCTAssertTrue(view.allowMouseReporting)
        XCTAssertFalse(view.isHoldingSelection)
        XCTAssertFalse(view.selectionActive)
    }

    internal func testAnOptionClickWithoutADragGivesTheMouseBack() async throws {
        let view = makeView()

        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: true))
        XCTAssertFalse(view.allowMouseReporting)
        view.handleMouseEvent(try mouseEvent(.leftMouseUp, option: false))
        XCTAssertFalse(view.allowMouseReporting, "the view still has to handle this mouse-up")
        await AsyncWait.drainMainQueue()

        XCTAssertTrue(view.allowMouseReporting)
        XCTAssertFalse(view.isHoldingSelection)
    }

    internal func testPlainAndOutsideClicksKeepMouseReporting() throws {
        let view = makeView()

        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: false))
        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: true, at: NSPoint(x: 900, y: 900)))
        view.handleMouseEvent(try mouseEvent(.leftMouseUp, option: true))
        view.handleMouseEvent(try mouseEvent(.rightMouseDown, option: true))

        XCTAssertTrue(view.allowMouseReporting)
        XCTAssertFalse(view.isHoldingSelection)
    }

    internal func testKeysOfTheFocusedPane() throws {
        let view = makeView()
        let window = makeWindow()
        window.contentView?.addSubview(view)
        XCTAssertTrue(window.makeFirstResponder(view))
        defer {
            view.removeFromSuperview()
        }

        view.handleKeyEvent(try keyEvent("a", command: true, window: window))
        XCTAssertTrue(view.isHoldingSelection, "⌘A selects everything and holds it")
        view.handleKeyEvent(try keyEvent("c", command: true, window: window))
        XCTAssertTrue(view.isHoldingSelection, "⌘C copies and keeps the selection")
        view.handleKeyEvent(try keyEvent("x", window: window))
        XCTAssertFalse(view.isHoldingSelection, "typing goes back to the program")
        XCTAssertTrue(view.allowMouseReporting)
        view.handleKeyEvent(try keyEvent("y", window: window))
        XCTAssertTrue(view.allowMouseReporting)
    }

    internal func testKeysOfAnotherViewAreIgnored() throws {
        let view = makeView()

        view.handleKeyEvent(try keyEvent("a", command: true))

        XCTAssertFalse(view.isHoldingSelection)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    internal func testTheMonitorSeesOptionClicksInTheWindow() async throws {
        let view = makeView()
        let first = makeWindow()
        let second = makeWindow()
        first.contentView?.addSubview(view)
        second.contentView?.addSubview(view)

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: NSPoint(x: 10, y: 10),
                modifierFlags: [.option],
                timestamp: 0,
                windowNumber: second.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        view.handleMouseEvent(try mouseEvent(.leftMouseDown, option: true))
        NSApp.postEvent(event, atStart: true)
        await AsyncWait.drainMainQueue(seconds: 0.3)

        XCTAssertTrue(view.allowMouseReporting, "the posted mouse-up went through the monitor")
        XCTAssertFalse(view.isHoldingSelection)
        view.removeFromSuperview()
        XCTAssertNil(view.window)
    }

    internal func testRightClickMenuOffersCopyPasteAndSelectAll() throws {
        let view = makeView()

        let menu = try XCTUnwrap(view.menu(for: try mouseEvent(.rightMouseDown, option: false)))
        let items = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(items.map(\.title), ["Copy", "Paste", "Select All"])
        XCTAssertEqual(
            items.map(\.action),
            [
                #selector(PaneTerminalView.copy(_:)),
                #selector(PaneTerminalView.paste(_:)),
                #selector(PaneTerminalView.selectAllText(_:))
            ]
        )
        XCTAssertTrue(items.allSatisfy { $0.target === view })
        XCTAssertEqual(items.map { view.validateUserInterfaceItem($0) }, [false, true, true], "Copy needs a selection")
    }

    internal func testSelectAllThenCopyPutsTheTextOnThePasteboard() {
        let view = makeView()
        view.feed(text: "hello from the pane")
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }

        view.selectAllText(nil)
        view.copy(self)

        XCTAssertTrue(view.isHoldingSelection)

        XCTAssertEqual(pasteboard.string(forType: .string)?.contains("hello from the pane"), true)
    }

    deinit {
        // Nothing to clean up.
    }
}
