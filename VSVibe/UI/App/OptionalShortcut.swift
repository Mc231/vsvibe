import SwiftUI

/// Applies a keyboard shortcut only when a key is provided.
internal struct OptionalShortcut: ViewModifier {
    internal let key: String?
    internal let modifiers: EventModifiers

    internal func body(content: Content) -> some View {
        if let key, let char = key.first {
            content.keyboardShortcut(KeyEquivalent(char), modifiers: modifiers)
        } else {
            content
        }
    }
}
