import SwiftUI

internal struct LabelEditorView: View {
    private enum Layout {
        static let width: CGFloat = 420
        static let headerSpacing: CGFloat = 10
        static let headerIconWidth: CGFloat = 26
        static let titleSpacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 20
        static let headerVerticalPadding: CGFloat = 14
        static let formSpacing: CGFloat = 16
        static let colorSpacing: CGFloat = 2
        static let colorVerticalPadding: CGFloat = 3
        static let symbolSpacing: CGFloat = 4
        static let formVerticalPadding: CGFloat = 18
        static let footerVerticalPadding: CGFloat = 12
        static let fieldSpacing: CGFloat = 6
    }

    internal let mode: LabelEditorMode
    /// Colors already taken, used to pre-select an unused one when creating.
    internal let usedColors: [String]
    internal let onSave: (LabelEditorResult) -> Void
    internal let onCancel: () -> Void

    @State private var name: String = ""
    @State private var colorHex: String = LabelPalette.defaultColor
    @State private var symbolName: String = LabelPalette.defaultSymbol

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: Layout.width)
        .onAppear { populate() }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty }

    private var header: some View {
        HStack(spacing: Layout.headerSpacing) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(Color(labelHex: colorHex))
                .frame(width: Layout.headerIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text(mode.isCreate ? "New Label" : "Edit Label")
                    .font(.headline)
                Text(trimmedName.isEmpty ? "Group projects in the sidebar" : trimmedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.headerVerticalPadding)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Layout.formSpacing) {
            field("Name") {
                TextField("Work, Pet projects, Clients…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Color") {
                FlowLayout(spacing: Layout.colorSpacing, lineSpacing: Layout.colorSpacing) {
                    ForEach(LabelPalette.colors, id: \.self) { hex in
                        ColorSwatch(hex: hex, isSelected: hex == colorHex) {
                            colorHex = hex
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Layout.colorVerticalPadding)
            }

            field("Icon") {
                FlowLayout(spacing: Layout.symbolSpacing, lineSpacing: Layout.symbolSpacing) {
                    ForEach(LabelPalette.symbols, id: \.self) { symbol in
                        SymbolSwatch(
                            symbol: symbol,
                            tint: Color(labelHex: colorHex),
                            isSelected: symbol == symbolName
                        ) {
                            symbolName = symbol
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.formVerticalPadding)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(mode.isCreate ? "Create" : "Save") {
                guard canSave else {
                    return
                }
                onSave(LabelEditorResult(name: trimmedName, colorHex: colorHex, symbolName: symbolName))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.footerVerticalPadding)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func populate() {
        switch mode {
        case .create:
            name = ""
            let used = Set(usedColors)
            colorHex = LabelPalette.colors.first { !used.contains($0) } ?? LabelPalette.defaultColor
            symbolName = LabelPalette.defaultSymbol

        case .edit(let label):
            name = label.name
            colorHex = label.colorHex
            symbolName = label.symbolName
        }
    }
}
