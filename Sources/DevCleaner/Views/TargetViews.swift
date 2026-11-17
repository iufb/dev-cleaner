import SwiftUI
import AppKit

struct TargetListView: View {
    let category: CleanupTarget.Category
    @Environment(CleanerStore.self) private var store

    private var items: [CleanupTarget] {
        store.targets.filter { $0.category == category }
    }

    var body: some View {
        List {
            Section {
                ForEach(items) { TargetRow(target: $0) }
            } header: {
                HStack {
                    Text(category.subtitle)
                    Spacer()
                    Button("Выбрать безопасные") { store.selectSafe(in: category) }
                    Button("Снять всё") { store.deselectAll(in: category) }
                }
                .buttonStyle(.link)
            }
        }
        .navigationTitle(category.title)
        .navigationSubtitle(Format.bytes(store.total(for: category)))
    }
}

struct TargetRow: View {
    let target: CleanupTarget
    @Environment(CleanerStore.self) private var store

    private var isOn: Binding<Bool> {
        Binding(
            get: { store.selection.contains(target.id) },
            set: { store.setSelected(target.id, $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!store.isAvailable(target) || store.isCleaning)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(target.name).font(.headline)
                    if target.risk == .caution {
                        Text("осторожно")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if target.isCommand {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                            .help("Выполняется командой")
                    }
                }
                Text(target.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(target.displayLocation)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            sizeLabel
                .frame(minWidth: 80, alignment: .trailing)

            Button {
                let existing = target.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                NSWorkspace.shared.activateFileViewerSelecting(existing)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Показать в Finder")
            .disabled(store.measurements[target.id]?.exists != true)
        }
        .padding(.vertical, 4)
        .opacity(store.isAvailable(target) ? 1 : 0.5)
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if store.cleaningTargetID == target.id {
            ProgressView().controlSize(.small)
        } else if store.scanning.contains(target.id) {
            ProgressView().controlSize(.small)
        } else if target.paths.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else if store.measurements[target.id]?.exists == true {
            Text(Format.bytes(store.size(of: target)))
                .monospacedDigit()
                .fontWeight(store.size(of: target) > 1_000_000_000 ? .semibold : .regular)
        } else {
            Text("нет").foregroundStyle(.tertiary)
        }
    }
}
