import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case category(CleanupTarget.Category)
    case projects
    case log
}

struct ContentView: View {
    @Environment(CleanerStore.self) private var store
    @State private var sidebar: SidebarItem? = .overview
    @State private var confirmClean = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            List(selection: $sidebar) {
                Section {
                    Label("Сводка", systemImage: "chart.bar.xaxis")
                        .tag(SidebarItem.overview)
                }

                Section("Глобальные кэши") {
                    ForEach(CleanupTarget.Category.allCases) { category in
                        HStack {
                            Label(category.title, systemImage: category.icon)
                            Spacer()
                            Text(Format.bytes(store.total(for: category)))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.category(category))
                    }
                }

                Section("Проекты") {
                    Label("Артефакты сборки", systemImage: "folder.badge.gearshape")
                        .tag(SidebarItem.projects)
                }

                Section {
                    Label("Журнал", systemImage: "list.bullet.rectangle")
                        .badge(store.log.count)
                        .tag(SidebarItem.log)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                DiskUsageView().padding()
            }
        } detail: {
            switch sidebar ?? .overview {
            case .overview:
                OverviewView(onOpen: { sidebar = .category($0) })
            case .category(let category):
                TargetListView(category: category)
            case .projects:
                ProjectsView()
            case .log:
                LogView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                }

                Button {
                    Task { await store.scanAll() }
                } label: {
                    Label("Пересчитать", systemImage: "arrow.clockwise")
                }
                .help("Пересчитать размеры")
                .disabled(store.isBusy)

                Toggle(isOn: $store.useTrash) {
                    Label("В Корзину", systemImage: "trash")
                }
                .help("Перемещать в Корзину вместо удаления. Место освободится только после очистки Корзины.")

                Button {
                    confirmClean = true
                } label: {
                    Label("Очистить \(Format.bytes(store.selectedSize))", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selection.isEmpty || store.isBusy)
            }
        }
        .sheet(isPresented: $confirmClean) {
            ConfirmationSheet(
                title: "Очистить выбранное (\(store.selection.count))?",
                groups: confirmationGroups,
                notes: [store.useTrash
                        ? "Файлы будут перемещены в Корзину."
                        : "Файлы будут удалены безвозвратно. Безопасные кэши восстановятся сами при следующей сборке или установке."],
                confirmTitle: "Очистить \(Format.bytes(store.selectedSize))"
            ) {
                Task { await store.cleanSelected() }
            }
        }
    }
}

extension ContentView {
    fileprivate var confirmationGroups: [ConfirmationSheet.Group] {
        func rows(_ risk: CleanupTarget.Risk) -> [ConfirmationSheet.Row] {
            store.selectedTargets.filter { $0.risk == risk }.map { target in
                ConfirmationSheet.Row(
                    id: target.id,
                    title: target.name,
                    subtitle: target.displayLocation,
                    size: target.paths.isEmpty ? "команда" : Format.bytes(store.size(of: target))
                )
            }
        }
        return [
            .init(title: "Осторожно: долго восстанавливать или нельзя восстановить", rows: rows(.caution), warning: true),
            .init(title: "Безопасно", rows: rows(.safe)),
        ]
    }
}

struct DiskUsageView: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        if let disk = store.disk {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(disk.used), total: Double(disk.total))
                    .tint(disk.freeFraction < 0.1 ? .red : (disk.freeFraction < 0.2 ? .orange : .accentColor))
                Text("Свободно \(Format.bytes(disk.available)) из \(Format.bytes(disk.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
