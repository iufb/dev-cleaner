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
            CardPage {
                RowCard(items: listItems) { item in
                    switch item {
                    case .group(let group, let open):
                        ArtifactGroupRow(group: group, expanded: open) {
                            withAnimation(.snappy(duration: 0.2)) {
                                if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
                            }
                        }
                    case .artifact(let artifact):
                        ArtifactRow(artifact: artifact, showProject: grouping == .kind)
                    }
                }
            }
        }
    }

    /// Строки карточки: группы и, у раскрытых, их артефакты.
    private enum ListItem: Identifiable {
        case group(CleanerStore.ArtifactGroup, open: Bool)
        case artifact(ProjectArtifact)

        var id: String {
            switch self {
            case .group(let group, _): "group:" + group.id
            case .artifact(let artifact): "item:" + artifact.url.path
            }
        }
    }

    private var listItems: [ListItem] {
        store.artifactGroups(by: grouping).flatMap { group -> [ListItem] in
            let open = expanded.contains(group.id)
            return [.group(group, open: open)] + (open ? group.items.map(ListItem.artifact) : [])
        }
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

/// Строка группы: проект (типы чипами, папка, когда трогали) или тип (в скольких проектах).
/// Галочка выбирает всю группу, клик по строке раскрывает её.
private struct ArtifactGroupRow: View {
    let group: CleanerStore.ArtifactGroup
    let expanded: Bool
    let toggle: () -> Void
    @Environment(CleanerStore.self) private var store

    var body: some View {
        let chosen = group.items.filter { store.projectSelection.contains($0.id) }.count

        HStack(spacing: 10) {
            Toggle(sources: bindings, isOn: \.self) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(store.isCleaning)
                .accessibilityLabel(group.title)

            HStack(alignment: .center, spacing: 8) {
                Text(group.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .layoutPriority(2)
                if let url = group.projectURL {
                    ForEach(kinds.prefix(3), id: \.self) { Tag(text: $0) }
                    if kinds.count > 3 { Tag(text: "+\(kinds.count - 3)") }
                    Text(Paths.display(url.deletingLastPathComponent()))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("в " + Format.count(group.items.count, "проекте", "проектах", "проектах"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if group.projectURL != nil {
                Text(Format.relative(group.lastTouched))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Последнее изменение в проекте, без артефактов и .git")
            }
            SizeText(bytes: group.size)
                .frame(minWidth: 76, alignment: .trailing)
            DisclosureChevron(expanded: expanded)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .help(group.projectURL?.path ?? group.title)
        .contextMenu {
            Button(expanded ? "Свернуть" : "Раскрыть", action: toggle)
            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(group.projectURL.map { [$0] } ?? group.items.map(\.url))
            }
        }
        .rowChrome(selected: chosen > 0 && chosen == group.items.count)
    }

    private var kinds: [String] { group.items.map(\.kind) }

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

/// Строка артефакта внутри группы: с отступом, в одну линию, как строка цели в категориях.
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

            HStack(alignment: .center, spacing: 8) {
                if showProject {
                    // По типу: строка — проект, папку проекта видно рядом.
                    Text(artifact.projectName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(Paths.display(artifact.projectURL.deletingLastPathComponent()))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    // По проектам: путь проекта уже в строке группы, здесь только тип и имя папки.
                    Tag(text: artifact.kind)
                    if artifact.url.lastPathComponent != artifact.kind {
                        Text(artifact.url.lastPathComponent)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 12)

            if showProject {
                Text(Format.relative(artifact.lastTouched))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            SizeText(bytes: artifact.size)
                .frame(minWidth: 76, alignment: .trailing)
            RowMenu(label: "Действия с \(artifact.kind)") { actions }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !store.isCleaning { isOn.wrappedValue.toggle() } }
        .help(artifact.url.path)
        .contextMenu { actions }
        .rowChrome(selected: isOn.wrappedValue, indent: 26)
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
