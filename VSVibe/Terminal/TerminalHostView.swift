import AppKit
import SwiftTerm
import SwiftUI

internal struct TerminalHostView: NSViewRepresentable {
    private enum Appearance {
        static let fontSize: CGFloat = 12.5
        static let backgroundRed: CGFloat = 0.07
        static let backgroundGreen: CGFloat = 0.07
        static let backgroundBlue: CGFloat = 0.09
        static let foregroundRed: CGFloat = 0.92
        static let foregroundGreen: CGFloat = 0.92
        static let foregroundBlue: CGFloat = 0.94
        static let opaque: CGFloat = 1.0
    }

    @MainActor
    internal final class Coordinator {
        internal var onFocusChanged: (Bool) -> Void

        internal init(onFocusChanged: @escaping (Bool) -> Void) {
            self.onFocusChanged = onFocusChanged
        }

        deinit {
            // Holds only a closure; nothing to tear down.
        }
    }

    /// Container that reports whether keyboard focus is inside it.
    @MainActor
    internal final class FocusObservingContainerView: NSView {
        internal var onFocusChanged: ((Bool) -> Void)?
        private var observer: NSKeyValueObservation?
        private var hasReportedFocus = false
        private var reportedFocus = false
        private var focusCheckScheduled = false

        deinit {
            observer?.invalidate()
        }

        override internal func viewDidMoveToWindow() {
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
            guard !focusCheckScheduled else {
                return
            }
            focusCheckScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                focusCheckScheduled = false
                let view = window?.firstResponder as? NSView
                let focused = view.map { $0 === self || $0.isDescendant(of: self) } ?? false
                guard !hasReportedFocus || reportedFocus != focused else {
                    return
                }
                hasReportedFocus = true
                reportedFocus = focused
                onFocusChanged?(focused)
            }
        }
    }

    internal let terminalView: LocalProcessTerminalView
    internal let onFocusChanged: (Bool) -> Void

    internal func makeCoordinator() -> Coordinator {
        Coordinator(onFocusChanged: onFocusChanged)
    }

    internal func makeNSView(context _: Context) -> NSView {
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

    internal func updateNSView(_ nsView: NSView, context _: Context) {
        if let container = nsView as? FocusObservingContainerView {
            container.onFocusChanged = onFocusChanged
        }
    }

    private func configureAppearance(_ view: LocalProcessTerminalView) {
        if let font = NSFont(name: "SF Mono", size: Appearance.fontSize)
            ?? NSFont(name: "Menlo", size: Appearance.fontSize) {
            view.font = font
        }
        view.nativeBackgroundColor = NSColor(
            calibratedRed: Appearance.backgroundRed,
            green: Appearance.backgroundGreen,
            blue: Appearance.backgroundBlue,
            alpha: Appearance.opaque
        )
        view.nativeForegroundColor = NSColor(
            calibratedRed: Appearance.foregroundRed,
            green: Appearance.foregroundGreen,
            blue: Appearance.foregroundBlue,
            alpha: Appearance.opaque
        )
    }
}
