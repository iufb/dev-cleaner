import SwiftUI
import AppKit

struct ProjectsView: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    pickFolder()
                } label: {
                    Label(store.projectRoot.path, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .help("Папка, в которой искать проекты")

                Picker("Проект не трогали", selection: $store.minAgeDays) {
                    Text("любые").tag(0)
                    Text("7+ дней").tag(7)
                    Text("30+ дней").tag(30)
                    Text("90+ дней").tag(90)
                }
                .fixedSize()

                Spacer()

                if store.isScanningProjects {
                    Button {
                        store.cancelProjectScan()
                    } label: {
                        Label("Остановить", systemImage: "stop.circle")
                    }
                }

                Button {
                    store.scanProjects()
                } label: {
                    Label(store.isScanningProjects ? "Заново" : "Найти", systemImage: "magnifyingglass")
                }
                .help(store.isScanningProjects ? "Отменить текущий поиск и начать заново" : "Искать артефакты сборки")
                .disabled(store.isCleaning)
            }
            .padding()

            Divider()

            if store.isScanningProjects {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Ищу… найдено \(store.artifacts.count) · \(Format.bytes(store.foundSize))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 6)
                Divider()
            } else if !store.filteredArtifacts.isEmpty {
                foundSummary
                Divider()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Артефакты сборки")
    }

    private var allSelected: Bool {
        !store.filteredArtifacts.isEmpty && store.selectedArtifacts.count == store.filteredArtifacts.count
    }

    private var foundSummary: some View {
        HStack(spacing: 8) {
            Text("Найдено \(store.filteredArtifacts.count) · \(Format.bytes(store.filteredArtifacts.reduce(0) { $0 + $1.size }))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button(allSelected ? "Снять выбор" : "Выбрать все") {
                store.projectSelection = allSelected ? [] : Set(store.filteredArtifacts.map(\.id))
            }
            .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if store.isScanningProjects && store.artifacts.isEmpty {
            ProgressView("Ищу node_modules, Pods, build, target, .venv…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !store.didScanProjects {
            ContentUnavailableView {
                Label("Выберите папку с проектами", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Например ~/Developer или ~/Projects. Поиск по всей домашней папке тоже работает, но займёт больше времени.")
            } actions: {
                Button("Найти артефакты") { store.scanProjects() }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.filteredArtifacts.isEmpty && !store.isScanningProjects {
            ContentUnavailableView("Ничего не найдено",
                                   systemImage: "checkmark.circle",
                                   description: Text("Попробуйте другой фильтр по возрасту или другую папку."))
        } else {
            @Bindable var store = store
            Table(store.filteredArtifacts, selection: $store.projectSelection) {
                TableColumn("Проект") { artifact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.projectName)
                        Text(artifact.projectURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TableColumn("Что", value: \.kind)
                    .width(min: 110, ideal: 150)
                TableColumn("Размер") { artifact in
                    Text(Format.bytes(artifact.size)).monospacedDigit()
                }
                .width(min: 80, ideal: 90)
                TableColumn("Активность") { artifact in
                    Text(artifact.lastTouched, format: .relative(presentation: .named))
                        .foregroundStyle(artifact.ageDays > 90 ? .secondary : .primary)
                }
                .width(min: 100, ideal: 130)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Показать в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
                }
            }
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

struct LogView: View {
    @Environment(CleanerStore.self) private var store

    var body: some View {
        Group {
            if store.log.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "list.bullet.rectangle",
                                       description: Text("Здесь появятся результаты очистки."))
            } else {
                List(store.log) { entry in
                    HStack(alignment: .top) {
                        Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.ok ? .green : .red)
                        Text(entry.text).textSelection(.enabled)
                        Spacer()
                        Text(entry.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Журнал")
        .toolbar {
            ToolbarItem {
                Button("Очистить журнал", systemImage: "trash.slash") { store.clearLog() }
                    .disabled(store.log.isEmpty)
                    .help("Удалить все записи журнала")
            }
        }
    }
}
