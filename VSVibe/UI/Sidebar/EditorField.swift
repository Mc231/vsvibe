import SwiftUI

/// A captioned field of the project editor: an uppercase caption above its content.
internal struct EditorField: View {
    private enum Layout {
        static let spacing: CGFloat = 6
    }

    private let label: String
    private let content: AnyView

    internal var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }

    internal init(label: String, @ViewBuilder content: () -> some View) {
        self.label = label
        self.content = AnyView(content())
    }
}
