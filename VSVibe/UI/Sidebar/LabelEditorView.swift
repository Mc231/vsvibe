import SwiftUI

enum LabelEditorMode: Identifiable, Equatable {
    /// Create a label; when `assignTo` is set the new label is applied to that
    /// project right away (used by the row context menu).
    case create(assignTo: FolderEntry.ID?)
    case edit(label: ProjectLabel)

    var id: String {
        switch self {
        case .create(let assignTo): "create:\(assignTo?.uuidString ?? "-")"
        case .edit(let label): "edit:\(label.id.uuidString)"
        }
    }

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}

struct LabelEditorResult {
    let name: String
    let colorHex: String
    let symbolName: String
}

struct LabelEditorView: View {
    let mode: LabelEditorMode
    /// Colors already taken, used to pre-select an unused one when creating.
    let usedColors: [String]
    let onSave: (LabelEditorResult) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var colorHex: String = LabelPalette.defaultColor
    @State private var symbolName: String = LabelPalette.defaultSymbol

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear { populate() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(Color(labelHex: colorHex))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.isCreate ? "New Label" : "Edit Label")
                    .font(.headline)
                Text(trimmedName.isEmpty ? "Group projects in the sidebar" : trimmedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Name") {
                TextField("Work, Pet projects, Clients…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Color") {
                FlowLayout(spacing: 2, lineSpacing: 2) {
                    ForEach(LabelPalette.colors, id: \.self) { hex in
                        ColorSwatch(hex: hex, isSelected: hex == colorHex) {
                            colorHex = hex
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            }

            field("Icon") {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(LabelPalette.symbols, id: \.self) { symbol in
                        SymbolSwatch(symbol: symbol,
                                     tint: Color(labelHex: colorHex),
                                     isSelected: symbol == symbolName) {
                            symbolName = symbol
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(mode.isCreate ? "Create" : "Save") {
                guard canSave else { return }
                onSave(LabelEditorResult(name: trimmedName, colorHex: colorHex, symbolName: symbolName))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

private struct ColorSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(labelHex: hex))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.8 : 0.0), lineWidth: 2)
                        .padding(-3)
                )
                // Keep the selection ring inside the swatch's own bounds so it
                // never clips against the sheet edge.
                .padding(4)
        }
        .buttonStyle(.plain)
        .help(hex)
    }
}

private struct SymbolSwatch: View {
    let symbol: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? tint : Color.secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? tint.opacity(0.18) : Color.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}
