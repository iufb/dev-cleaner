import SwiftUI
import AppKit

/// Артефакты сборки: группы по проекту или по типу, фильтры чипсами, удаление через общую плашку выбора.
struct ProjectsView: View {
    @Environment(CleanerStore.self) private var store
    @State private var grouping: CleanerStore.ArtifactGrouping = .project
    @State private var expanded: Set<String> = []

    private static let defaultAge = 30

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isScanningProjects {
                scanningBanner
                Divider()
            }
            if store.didScanProjects && !store.artifacts.isEmpty {
                filters
                Divider()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Артефакты сборки")
        .toolbar {
            ToolbarItem(placement: .principal) {
                SegmentedControl(selection: $grouping, options: [
                    (.project, "По проектам"),
                    (.kind, "По типу"),
                ])
                .disabled(!store.didScanProjects)
                .help("Группировать по проектам или по типу артефакта")
            }
        }
    }

    // MARK: - Шапка и фильтры

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: pickFolder) {
                Label(Paths.display(store.projectRoot), systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .buttonStyle(.secondary)
            .fixedSize()
            .help("Папка, в которой искать проекты: \(store.projectRoot.path)")

            if store.didScanProjects && !store.filteredArtifacts.isEmpty {
                summaryText
                summary
            }

            Spacer(minLength: 8)

            // До первого поиска главное действие — кнопка в пустом состоянии.
            if store.didScanProjects {
                Button {
                    store.scanProjects()
                } label: {
                    Label("Заново", systemImage: "magnifyingglass")
                }
                .buttonStyle(.secondary)
                .fixedSize()
                .help(store.isScanningProjects ? "Отменить текущий поиск и начать заново" : "Искать артефакты сборки заново")
                .disabled(store.isCleaning)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var scanningBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Ищу в \(Paths.display(store.projectRoot))… найдено \(store.artifacts.count) · \(Format.bytes(store.foundSize))")
                .monospacedDigit()
            Spacer()
            Button("Остановить") { store.cancelProjectScan() }
                .buttonStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private var filters: some View {
        @Bindable var store = store
        let kinds = store.artifactKinds
        let filtersOn = store.minAgeDays != Self.defaultAge || !store.kindFilter.isEmpty

        return HStack(spacing: 12) {
            Text("Не трогали")
                .foregroundStyle(.secondary)
                .fixedSize()
            SegmentedControl(selection: $store.minAgeDays, options: [
                (0, "Любые"),
                (7, "7+ дн"),
                (30, "30+ дн"),
                (90, "90+ дн"),
            ])

            SelectButton(title: kindTitle) {
                KindPicker(kinds: kinds)
            }
            .disabled(kinds.isEmpty)

            if filtersOn {
                Button("Сбросить") {
                    store.minAgeDays = Self.defaultAge
                    store.kindFilter = []
                }
                .buttonStyle(.quiet)
                .fixedSize()
            }

            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var kindTitle: String {
        let chosen = store.kindFilter.sorted()
        switch chosen.count {
        case 0: return "Все типы"
        case 1: return chosen[0]
        default: return Format.count(chosen.count, "тип", "типа", "типов")
        }
    }

    private var summaryText: some View {
        let items = store.filteredArtifacts
        let projects = Set(items.map(\.projectURL)).count
        return Text("\(Format.count(projects, "проект", "проекта", "проектов")) · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(-1)
    }

    private var summary: some View {
        let items = store.filteredArtifacts
        let all = !items.isEmpty && store.selectedArtifacts.count == items.count
        return Button(all ? "Снять выбор" : "Выбрать все") {
            store.projectSelection = all ? [] : Set(items.map(\.id))
        }
        .buttonStyle(.quiet)
        .disabled(items.isEmpty)
        .fixedSize()
    }

    // MARK: - Список

    @ViewBuilder
    private var content: some View {
        if store.isScanningProjects && store.artifacts.isEmpty {
            ProgressView("Ищу node_modules, Pods, build, target, .venv…")
        } else if !store.didScanProjects {
            ContentUnavailableView {
                Label("Найдите артефакты сборки", systemImage: "folder.badge.gearshape")
            } description: {
                Text("node_modules, Pods, build, target, .venv и другое в \(Paths.display(store.projectRoot)). Папку можно сменить кнопкой слева сверху.")
            } actions: {
                Button("Найти артефакты") { store.scanProjects() }
                    .buttonStyle(.primary(.large))
            }
        } else if store.filteredArtifacts.isEmpty && !store.isScanningProjects {
            ContentUnavailableView("Ничего не найдено",
                                   systemImage: "checkmark.circle",
                                   description: Text(store.artifacts.isEmpty
                                       ? "В \(Paths.display(store.projectRoot)) нет артефактов сборки."
                                       : "Под фильтры ничего не попало. Попробуйте «Не трогали: Любые» или другой тип."))
        } else {
            List {
                ForEach(store.artifactGroups(by: grouping)) { group in
                    DisclosureGroup(isExpanded: expansion(group.id)) {
                        ForEach(group.items) { artifact in
                            ArtifactRow(artifact: artifact, showProject: grouping == .kind)
                        }
                    } label: {
                        ArtifactGroupRow(group: group)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }
        )
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.projectRoot
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            store.setProjectRoot(url)
        }
    }
}

/// Строка группы: проект (путь, когда трогали) или тип (сколько проектов). Галочка на всю группу.
private struct ArtifactGroupRow: View {
    let group: CleanerStore.ArtifactGroup
    @Environment(CleanerStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Toggle(sources: bindings, isOn: \.self) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(store.isCleaning)
                .accessibilityLabel(group.title)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if group.projectURL != nil {
                Text(Format.relative(group.lastTouched))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Последнее изменение в проекте, без артефактов и .git")
            }
            Text(Format.bytes(group.size))
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(group.projectURL.map { [$0] } ?? group.items.map(\.url))
            }
        }
    }

    private var subtitle: String {
        if let url = group.projectURL {
            let kinds = group.items.map(\.kind).joined(separator: ", ")
            return "\(kinds) · \(Paths.display(url.deletingLastPathComponent()))"
        }
        return "в " + Format.count(group.items.count, "проекте", "проектах", "проектах")
    }

    private var bindings: [Binding<Bool>] {
        group.items.map { artifact in
            Binding(
                get: { store.projectSelection.contains(artifact.id) },
                set: { on in
                    if on { store.projectSelection.insert(artifact.id) } else { store.projectSelection.remove(artifact.id) }
                }
            )
        }
    }
}

/// Строка артефакта в одну линию, как строка цели в категориях.
private struct ArtifactRow: View {
    let artifact: ProjectArtifact
    let showProject: Bool
    @Environment(CleanerStore.self) private var store

    private var isOn: Binding<Bool> {
        Binding(
            get: { store.projectSelection.contains(artifact.id) },
            set: { on in
                if on { store.projectSelection.insert(artifact.id) } else { store.projectSelection.remove(artifact.id) }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(store.isCleaning)
                .accessibilityLabel("\(artifact.projectName), \(artifact.kind)")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(showProject ? artifact.projectName : artifact.kind)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(Paths.display(artifact.url))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if showProject {
                Text(Format.relative(artifact.lastTouched))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(Format.bytes(artifact.size))
                .monospacedDigit()
                .frame(minWidth: 76, alignment: .trailing)

            Menu {
                actions
            } label: {
                MoreMenuLabel()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Действия")
            .accessibilityLabel("Действия с \(artifact.kind)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if !store.isCleaning { isOn.wrappedValue.toggle() } }
        .help(artifact.url.path)
        .contextMenu { actions }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([artifact.url]) }
        Button("Скопировать путь") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(artifact.url.path, forType: .string)
        }
    }
}

/// Всплывающий список типов артефактов с галочками.
private struct KindPicker: View {
    let kinds: [String]
    @Environment(CleanerStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(kinds, id: \.self) { kind in
                Toggle(kind, isOn: Binding(
                    get: { store.kindFilter.contains(kind) },
                    set: { on in
                        if on { store.kindFilter.insert(kind) } else { store.kindFilter.remove(kind) }
                    }
                ))
                .toggleStyle(.checkbox)
            }
            Divider()
            Button("Все типы") { store.kindFilter = [] }
                .buttonStyle(.quiet)
                .disabled(store.kindFilter.isEmpty)
        }
        .padding(14)
        .frame(minWidth: 220, alignment: .leading)
    }
}
