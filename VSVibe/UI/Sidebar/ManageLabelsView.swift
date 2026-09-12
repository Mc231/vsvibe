import SwiftUI

/// Sheet listing every label: reorder (drag), edit, delete, add.
struct ManageLabelsView: View {
    @Environment(AppEnvironment.self) private var env
    let onClose: () -> Void

    @State private var selection: ProjectLabel.ID?

    private var labels: [ProjectLabel] { env.folderStore.labels }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 440, height: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Labels")
                    .font(.headline)
                Text("Drag to reorder — the order is used for the sidebar sections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if labels.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
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
                        .onTapGesture(count: 2) { env.beginEditLabelFlow(label) }
                }
                .onMove { source, dest in
                    env.folderStore.moveLabels(fromOffsets: source, toOffset: dest)
                }
            }
        }
    }

    private func row(_ label: ProjectLabel) -> some View {
        let count = env.folderStore.folders.filter { $0.labelIDs.contains(label.id) }.count
        return HStack(spacing: 10) {
            Image(systemName: label.symbolName)
                .foregroundStyle(label.color)
                .frame(width: 18)
            Text(label.name)
            Spacer(minLength: 0)
            Text(count == 1 ? "1 project" : "\(count) projects")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                env.beginEditLabelFlow(label)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Edit Label")
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                env.beginCreateLabelFlow()
            } label: {
                Image(systemName: "plus").frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("New Label")

            Button {
                if let id = selection {
                    env.folderStore.deleteLabel(id: id)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus").frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("Delete Label (projects are kept)")

            Spacer()
            Button("Done") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
