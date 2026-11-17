import SwiftUI
import AppKit

struct ProjectsView: View {
    @Environment(CleanerStore.self) private var store
    @State private var confirmDelete = false

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
                .frame(width: 260)

                Spacer()

                Button {
                    Task { await store.scanProjects() }
                } label: {
                    Label("Найти", systemImage: "magnifyingglass")
                }
                .disabled(store.isBusy)
            }
            .padding()

            Divider()

            content

            Divider()

            HStack {
                Text("Выбрано: \(store.selectedArtifacts.count) · \(Format.bytes(store.selectedArtifacts.reduce(0) { $0 + $1.size }))")
                    .monospacedDigit()
                Spacer()
                Button("Выбрать все") {
                    store.projectSelection = Set(store.filteredArtifacts.map(\.id))
                }
                .disabled(store.filteredArtifacts.isEmpty)
                Button("Удалить выбранное", role: .destructive) {
                    confirmDelete = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.selectedArtifacts.isEmpty || store.isBusy)
            }
            .padding()
        }
        .navigationTitle("Артефакты сборки")
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
                notes: ["node_modules, Pods, build и подобное восстанавливаются командами npm install, pod install или сборкой проекта."],
                confirmTitle: "Удалить \(Format.bytes(store.selectedArtifacts.reduce(0) { $0 + $1.size }))"
            ) {
                Task { await store.deleteSelectedArtifacts() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isScanningProjects {
            ProgressView("Ищу node_modules, Pods, build, target, .venv…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !store.didScanProjects {
            ContentUnavailableView {
                Label("Выберите папку с проектами", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Например ~/Developer или ~/Projects. Поиск по всей домашней папке тоже работает, но займёт больше времени.")
            } actions: {
                Button("Найти") { Task { await store.scanProjects() } }
            }
        } else if store.filteredArtifacts.isEmpty {
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
            store.projectRoot = url
            store.didScanProjects = false
            store.artifacts = []
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
