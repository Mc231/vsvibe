import AppKit
import SwiftUI
import SwiftTerm

struct TerminalHostView: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView
    let onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocusChanged: onFocusChanged)
    }

    func makeNSView(context: Context) -> NSView {
        let container = FocusObservingContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onFocusChanged = onFocusChanged

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        configureAppearance(terminalView)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let container = nsView as? FocusObservingContainerView {
            container.onFocusChanged = onFocusChanged
        }
    }

    private func configureAppearance(_ view: LocalProcessTerminalView) {
        if let font = NSFont(name: "SF Mono", size: 12.5) ?? NSFont(name: "Menlo", size: 12.5) {
            view.font = font
        }
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
        view.nativeForegroundColor = NSColor(calibratedRed: 0.92, green: 0.92, blue: 0.94, alpha: 1.0)
    }

    @MainActor
    final class Coordinator {
        var onFocusChanged: (Bool) -> Void
        init(onFocusChanged: @escaping (Bool) -> Void) {
            self.onFocusChanged = onFocusChanged
        }
    }
}

@MainActor
final class FocusObservingContainerView: NSView {
    var onFocusChanged: ((Bool) -> Void)?
    private var observer: NSKeyValueObservation?
    private var reportedFocus: Bool?
    private var focusCheckScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observer?.invalidate()
        observer = nil
        guard let window else {
            scheduleFocusCheck()
            return
        }
        observer = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.scheduleFocusCheck()
            }
        }
        scheduleFocusCheck()
    }

    private func scheduleFocusCheck() {
        // AppKit can change firstResponder while SwiftUI is mounting a pane or
        // dismissing a sheet. Publish after that update, and only on a change.
        guard !focusCheckScheduled else { return }
        focusCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusCheckScheduled = false
            let view = self.window?.firstResponder as? NSView
            let focused = view.map { $0 === self || $0.isDescendant(of: self) } ?? false
            guard self.reportedFocus != focused else { return }
            self.reportedFocus = focused
            self.onFocusChanged?(focused)
        }
    }

    deinit {
        observer?.invalidate()
    }
}
