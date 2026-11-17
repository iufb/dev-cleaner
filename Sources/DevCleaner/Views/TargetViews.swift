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
            if category == .system && !store.hasFullDiskAccess {
                Section {
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
                .disabled(!canToggle)
                .accessibilityLabel(target.name)

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
                    .help(target.displayLocation)
            }

            Spacer(minLength: 12)

            sizeLabel
                .frame(minWidth: 80, alignment: .trailing)

            Button(action: revealInFinder) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Показать в Finder")
            .accessibilityLabel("Показать в Finder")
            .disabled(!existsOnDisk)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // Строка целиком — область нажатия, как у чекбокса с подписью.
        .onTapGesture { if canToggle { isOn.wrappedValue.toggle() } }
        .opacity(store.isAvailable(target) ? 1 : 0.5)
        .contextMenu {
            Button("Показать в Finder", action: revealInFinder).disabled(!existsOnDisk)
            Button(target.isCommand ? "Скопировать команду" : "Скопировать путь") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyText, forType: .string)
            }
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
        if store.cleaningTargetID == target.id {
            ProgressView().controlSize(.small)
        } else if store.scanning.contains(target.id) {
            ProgressView().controlSize(.small)
        } else if !store.isInstalled(target) {
            Text("не установлено").foregroundStyle(.tertiary)
                .help("\(target.requiredTool ?? "Инструмент") не найден в PATH")
        } else if target.paths.isEmpty {
            Text("—").foregroundStyle(.secondary)
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
