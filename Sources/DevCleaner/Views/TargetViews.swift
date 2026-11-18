import SwiftUI
import AppKit

/// Цели одной категории: группы «Безопасно» и «Осторожно», пустое свёрнуто внизу.
struct TargetListView: View {
    let category: CleanupTarget.Category
    @Environment(CleanerStore.self) private var store
    @State private var showInactive = false

    var body: some View {
        let groups = store.groups(in: category)

        List {
            if category == .system && !store.hasFullDiskAccess {
                Section { FullDiskAccessBanner() }
            }

            if !groups.safe.isEmpty {
                Section {
                    ForEach(groups.safe) { TargetRow(target: $0) }
                } header: {
                    GroupHeader(title: "Безопасно · восстановится само", targets: groups.safe, selectable: true)
                }
            }

            if !groups.caution.isEmpty {
                Section {
                    ForEach(groups.caution) { TargetRow(target: $0) }
                } header: {
                    GroupHeader(title: "Осторожно · долго или нельзя восстановить", targets: groups.caution, selectable: false)
                }
            }

            if groups.safe.isEmpty && groups.caution.isEmpty && store.scanning.isEmpty {
                Section {
                    Label("В этой категории сейчас нечего чистить.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if !groups.inactive.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showInactive) {
                        ForEach(groups.inactive) { TargetRow(target: $0) }
                    } label: {
                        Text("Пустые и не установленные · \(groups.inactive.count)")
                            .foregroundStyle(.secondary)
                            .help(groups.inactive.map(\.name).joined(separator: ", "))
                    }
                }
            }
        }
        .navigationTitle(category.title)
        .navigationSubtitle(Format.bytes(store.total(for: category)))
    }
}

/// Заголовок группы: сумма, сколько выбрано и, для безопасного, общая галочка.
private struct GroupHeader: View {
    let title: String
    let targets: [CleanupTarget]
    let selectable: Bool
    @Environment(CleanerStore.self) private var store

    var body: some View {
        let total = targets.reduce(0) { $0 + store.size(of: $1) }
        let chosen = targets.filter { store.selection.contains($0.id) }

        HStack(spacing: 8) {
            if selectable {
                Toggle(sources: bindings, isOn: \.self) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(store.isCleaning)
                    .help("Выбрать или снять всю группу")
            }
            Text(title)
            Spacer()
            Group {
                if chosen.isEmpty {
                    Text(Format.bytes(total))
                } else {
                    Text("выбрано \(chosen.count) из \(targets.count) · \(Format.bytes(total))")
                }
            }
            .monospacedDigit()
        }
    }

    private var bindings: [Binding<Bool>] {
        targets.map { target in
            Binding(
                get: { store.selection.contains(target.id) },
                set: { store.setSelected(target.id, $0) }
            )
        }
    }
}

private struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Нет Полного доступа к диску").font(.headline)
                Text("Без него нельзя очистить Корзину и бэкапы iPhone. Включите DevCleaner в Системных настройках и перезапустите приложение.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Открыть настройки") { FullDiskAccess.openSettings() }
        }
        .padding(.vertical, 6)
    }
}

/// Строка цели в одну линию. Полное описание и путь — в подсказке, действия — в «⋯» и правом клике.
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
        HStack(spacing: 10) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!canToggle)
                .accessibilityLabel(target.name)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(target.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .layoutPriority(1)
                if target.isCommand {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("команда")
                }
                Text(target.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            sizeLabel
                .frame(minWidth: 76, alignment: .trailing)

            Menu {
                actions
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Действия")
            .accessibilityLabel("Действия с «\(target.name)»")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        // Строка целиком — область нажатия, как у чекбокса с подписью.
        .onTapGesture { if canToggle { isOn.wrappedValue.toggle() } }
        .opacity(store.isAvailable(target) ? 1 : 0.55)
        .help("\(target.detail)\n\n\(target.displayLocation)")
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Показать в Finder", action: revealInFinder).disabled(!existsOnDisk)
        Button(target.isCommand ? "Скопировать команду" : "Скопировать путь") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyText, forType: .string)
        }
    }

    private var canToggle: Bool { store.isAvailable(target) && !store.isCleaning }
    private var existsOnDisk: Bool { store.measurements[target.id]?.exists == true }

    private var copyText: String {
        if case .command(let command) = target.action { return command }
        return target.urls.map(\.path).joined(separator: "\n")
    }

    private func revealInFinder() {
        let existing = target.urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }

    @ViewBuilder
    private var sizeLabel: some View {
        if store.cleaningTargetID == target.id || store.scanning.contains(target.id) {
            ProgressView().controlSize(.small)
        } else if !store.isInstalled(target) {
            Text("не установлено").foregroundStyle(.tertiary)
                .help("\(target.requiredTool ?? "Инструмент") не найден в PATH")
        } else if target.paths.isEmpty {
            Text("—").foregroundStyle(.secondary)
                .help("Размер заранее неизвестен: очищается командой")
        } else if existsOnDisk, store.size(of: target) == 0 {
            Text("пусто").foregroundStyle(.tertiary)
        } else if existsOnDisk {
            Text(Format.bytes(store.size(of: target)))
                .monospacedDigit()
                .fontWeight(store.size(of: target) > 1_000_000_000 ? .semibold : .regular)
        } else {
            Text("нет").foregroundStyle(.tertiary)
        }
    }
}
