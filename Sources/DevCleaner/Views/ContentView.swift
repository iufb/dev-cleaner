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
    @State private var confirmDelete = false

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
                            Label {
                                Text(category.title)
                            } icon: {
                                Image(systemName: category.icon).foregroundStyle(category.color)
                            }
                            Spacer()
                            if store.total(for: category) > 0 {
                                Text(Format.bytes(store.total(for: category)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
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
        } detail: {
            Group {
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
            .safeAreaInset(edge: .bottom, spacing: 0) { selectionBar }
            .animation(.snappy(duration: 0.22), value: barVisible)
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
                .disabled(store.isCacheBusy)
            }
        }
        .sheet(isPresented: $confirmClean) {
            ConfirmationSheet(
                title: "Очистить выбранное (\(store.selection.count))?",
                groups: confirmationGroups,
                useTrash: $store.useTrash,
                notes: confirmationNotes,
                confirmTitle: { _ in Format.cleanTitle(count: store.selection.count, size: store.selectedSize) }
            ) {
                Task { await store.cleanSelected() }
            }
        }
        .sheet(isPresented: $confirmDelete) {
            ConfirmationSheet(
                title: "Удалить \(store.selectedArtifacts.count) папок?",
                groups: [.init(title: "Артефакты сборки", rows: store.selectedArtifacts.map { artifact in
                    ConfirmationSheet.Row(
                        id: artifact.url.path,
                        title: "\(artifact.projectName) · \(artifact.kind)",
                        subtitle: artifact.url.path,
                        size: Format.bytes(artifact.size)
                    )
                })],
                useTrash: $store.useTrash,
                notes: { useTrash in
                    [useTrash
                        ? "Папки будут перемещены в Корзину. Место освободится после её очистки."
                        : "Папки будут удалены безвозвратно.",
                     "node_modules, Pods, build и подобное восстанавливаются командами npm install, pod install или сборкой проекта."]
                },
                confirmTitle: { useTrash in
                    "\(useTrash ? "В Корзину" : "Удалить") \(Format.bytes(selectedArtifactsSize))"
                }
            ) {
                Task { await store.deleteSelectedArtifacts() }
            }
        }
    }
}

// MARK: - Плашка выбора

extension ContentView {
    /// Какой выбор показывает плашка: артефакты на их экране, глобальные кэши на сводке и в категориях.
    private enum BarContext { case caches, artifacts, none }

    private var barContext: BarContext {
        switch sidebar ?? .overview {
        case .overview, .category:
            store.selection.isEmpty ? .none : .caches
        case .projects:
            store.selectedArtifacts.isEmpty ? .none : .artifacts
        case .log:
            .none
        }
    }

    private var barVisible: Bool { barContext != .none }

    private var selectedArtifactsSize: Int64 {
        store.selectedArtifacts.reduce(0) { $0 + $1.size }
    }

    @ViewBuilder
    private var selectionBar: some View {
        switch barContext {
        case .caches:
            SelectionBar(
                summary: store.selectedSize > 0
                    ? "Выбрано \(store.selection.count) · \(Format.bytes(store.selectedSize))"
                    : "Выбрано \(store.selection.count)",
                actionTitle: "Очистить…",
                busy: store.isCleaning,
                disabled: !store.scanning.isEmpty,
                onClear: { store.deselectAll() },
                onAction: { confirmClean = true }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .artifacts:
            SelectionBar(
                summary: "Выбрано \(store.selectedArtifacts.count) · \(Format.bytes(selectedArtifactsSize))",
                actionTitle: "Удалить…",
                destructive: true,
                busy: store.isCleaning,
                disabled: store.isScanningProjects,
                onClear: { store.projectSelection = [] },
                onAction: { confirmDelete = true }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .none:
            EmptyView()
        }
    }
}

extension ContentView {
    fileprivate func confirmationNotes(useTrash: Bool) -> [String] {
        var notes = [useTrash
            ? "Файлы будут перемещены в Корзину. Место освободится после её очистки."
            : "Файлы будут удалены безвозвратно. Безопасные кэши восстановятся сами при следующей сборке или установке."]
        let permanent = store.selectedTargets.filter(\.alwaysPermanent)
        if useTrash, !permanent.isEmpty {
            notes.append("«\(permanent.map(\.name).joined(separator: "», «"))» очищается безвозвратно, даже в режиме «В Корзину».")
        }
        return notes
    }

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
