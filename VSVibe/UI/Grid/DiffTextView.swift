import AppKit
import SwiftUI

/// Native text scrolling avoids creating thousands of SwiftUI diff-line views.
internal struct DiffTextView: NSViewRepresentable {
    private enum Layout {
        static let inset: CGFloat = 12
        static let fontSize: CGFloat = 12
    }

    internal let text: String

    private static func color(forLine line: String) -> NSColor? {
        if line.hasPrefix("+") {
            return .systemGreen
        }
        if line.hasPrefix("-") {
            return .systemRed
        }
        if line.hasPrefix("@@") {
            return .systemBlue
        }
        return nil
    }

    internal func makeNSView(context _: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isRichText = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = true
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: Layout.inset, height: Layout.inset)
        scroll.documentView = view
        return scroll
    }

    internal func updateNSView(_ scroll: NSScrollView, context _: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else {
            return
        }
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: Layout.fontSize, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
        )
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            let length = line.utf16.count
            if let color = Self.color(forLine: line) {
                attributed.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: offset, length: length)
                )
            }
            offset += length + 1
        }
        view.textStorage?.setAttributedString(attributed)
        // Reset both axes after AppKit lays out the new document. Scrolling the
        // selection into view can otherwise clip the start of long diff lines.
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else {
                return
            }
            scroll.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
