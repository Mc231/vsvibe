import SwiftUI

/// Sheet listing every label: reorder (drag), edit, delete, add.
internal struct ManageLabelsView: View {
    private enum Layout {
        static let width: CGFloat = 440
        static let height: CGFloat = 380
        static let headerSpacing: CGFloat = 10
        static let titleSpacing: CGFloat = 2
        static let headerHorizontalPadding: CGFloat = 20
        static let headerVerticalPadding: CGFloat = 14
        static let emptySpacing: CGFloat = 8
        static let emptyIconSize: CGFloat = 28
        static let doubleTapCount = 2
        static let rowIconWidth: CGFloat = 18
        static let rowVerticalPadding: CGFloat = 2
        static let footerSpacing: CGFloat = 6
        static let footerButtonSize: CGFloat = 22
        static let footerHorizontalPadding: CGFloat = 16
        static let footerVerticalPadding: CGFloat = 10
    }

    @Environment(AppEnvironment.self)
    private var env
    internal let onClose: () -> Void

    @State private var selection: ProjectLabel.ID?

    internal var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
    }

    private var labels: [ProjectLabel] { env.folderStore.labels }

    private var header: some View {
        HStack(spacing: Layout.headerSpacing) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Layout.titleSpacing) {
                Text("Labels")
                    .font(.headline)
                Text("Drag to reorder — the order is used for the sidebar sections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Layout.headerHorizontalPadding)
        .padding(.vertical, Layout.headerVerticalPadding)
    }

    @ViewBuilder private var content: some View {
        if labels.isEmpty {
            VStack(spacing: Layout.emptySpacing) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: Layout.emptyIconSize))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("No labels yet")
                    .foregroundStyle(.secondary)
                Text("Create one to group your projects in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(labels) { label in
                    row(label)
                        .tag(label.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: Layout.doubleTapCount) { env.beginEditLabelFlow(label) }
                }
                .onMove { source, dest in
                    env.folderStore.moveLabels(fromOffsets: source, toOffset: dest)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Layout.footerSpacing) {
            Button {
                env.beginCreateLabelFlow()
            } label: {
                Image(systemName: "plus")
                    .frame(width: Layout.footerButtonSize, height: Layout.footerButtonSize)
                    .accessibilityLabel("New Label")
            }
            .buttonStyle(.borderless)
            .help("New Label")

            Button {
                if let id = selection {
                    env.folderStore.deleteLabel(id: id)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: Layout.footerButtonSize, height: Layout.footerButtonSize)
                    .accessibilityLabel("Delete Label")
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Delete Label (projects are kept)")

            Spacer()
            Button("Done") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Layout.footerHorizontalPadding)
        .padding(.vertical, Layout.footerVerticalPadding)
    }

    private func row(_ label: ProjectLabel) -> some View {
        let count = env.folderStore.folders.filter { $0.labelIDs.contains(label.id) }.count
        return HStack(spacing: Layout.headerSpacing) {
            Image(systemName: label.symbolName)
                .foregroundStyle(label.color)
                .frame(width: Layout.rowIconWidth)
                .accessibilityHidden(true)
            Text(label.name)
            Spacer(minLength: 0)
            Text(count == 1 ? "1 project" : "\(count) projects")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                env.beginEditLabelFlow(label)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: Layout.rowIconWidth, height: Layout.rowIconWidth)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Edit Label")
            }
            .buttonStyle(.borderless)
            .help("Edit Label")
        }
        .padding(.vertical, Layout.rowVerticalPadding)
    }
}
