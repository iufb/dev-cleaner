import SwiftUI

/// Подтверждение удаления с полным списком того, что будет удалено.
struct ConfirmationSheet: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let size: String
    }

    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let rows: [Row]
        var warning = false
    }

    let title: String
    let groups: [Group]
    let notes: [String]
    let confirmTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())

            List {
                ForEach(groups.filter { !$0.rows.isEmpty }) { group in
                    Section {
                        ForEach(group.rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                    if !row.subtitle.isEmpty {
                                        Text(row.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                Text(row.size).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Label(group.title, systemImage: group.warning ? "exclamationmark.triangle.fill" : "checkmark.shield")
                            .foregroundStyle(group.warning ? .orange : .secondary)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 160, idealHeight: 280)

            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive) {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
