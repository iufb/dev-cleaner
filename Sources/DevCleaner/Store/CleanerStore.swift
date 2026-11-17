import Foundation
import Observation

@MainActor
@Observable
final class CleanerStore {
    struct Measurement: Sendable {
        var size: Int64
        var exists: Bool
        /// Для целей-команд: найден ли нужный инструмент. `nil` — проверка не нужна.
        var installed: Bool? = nil
    }

    // MARK: Кэши

    let targets: [CleanupTarget] = Catalog.all
    var measurements: [String: Measurement] = [:]
    var scanning: Set<String> = []
    var selection: Set<String> = []
    var isCleaning = false
    var cleaningTargetID: String?
    var useTrash = false
    var disk: DiskInfo? = DiskInfo.current()
    var log: [LogEntry] = []

    // MARK: Проекты

    var projectRoot: URL = ProjectScanner.defaultRoot()
    var artifacts: [ProjectArtifact] = []
    var projectSelection: Set<URL> = []
    var isScanningProjects = false
    var didScanProjects = false
    var minAgeDays = 30

    var isBusy: Bool { isCleaning || !scanning.isEmpty || isScanningProjects }

    // MARK: - Подсчёт

    func scanAll() async {
        scanning = Set(targets.map(\.id))

        await withTaskGroup(of: (String, Measurement).self) { group in
            for target in targets {
                let id = target.id
                let urls = target.urls
                let tool = target.requiredTool
                group.addTask(priority: .utility) {
                    let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                    let size = existing.reduce(Int64(0)) { $0 + SizeCalculator.size(of: $1) }
                    let installed = tool.map { Shell.which($0) != nil }
                    return (id, Measurement(size: size, exists: !existing.isEmpty, installed: installed))
                }
            }
            for await (id, measurement) in group {
                measurements[id] = measurement
                scanning.remove(id)
            }
        }

        disk = DiskInfo.current()
    }

    func size(of target: CleanupTarget) -> Int64 {
        measurements[target.id]?.size ?? 0
    }

    func isAvailable(_ target: CleanupTarget) -> Bool {
        if target.isCommand { return isInstalled(target) }
        return measurements[target.id]?.exists == true
    }

    func isInstalled(_ target: CleanupTarget) -> Bool {
        measurements[target.id]?.installed ?? true
    }

    func total(for category: CleanupTarget.Category) -> Int64 {
        targets.filter { $0.category == category }.reduce(0) { $0 + size(of: $1) }
    }

    var grandTotal: Int64 {
        targets.reduce(0) { $0 + size(of: $1) }
    }

    var selectedTargets: [CleanupTarget] {
        targets.filter { selection.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedTargets.reduce(0) { $0 + size(of: $1) }
    }

    // MARK: - Выбор

    func setSelected(_ id: String, _ isOn: Bool) {
        if isOn { selection.insert(id) } else { selection.remove(id) }
    }

    func selectSafe(in category: CleanupTarget.Category? = nil) {
        for target in targets where target.risk == .safe && (category == nil || target.category == category) {
            if size(of: target) > 0 { selection.insert(target.id) }
        }
    }

    func deselectAll(in category: CleanupTarget.Category? = nil) {
        for target in targets where category == nil || target.category == category {
            selection.remove(target.id)
        }
    }

    // MARK: - Очистка

    func cleanSelected() async {
        let chosen = targets.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }

        isCleaning = true
        let trash = useTrash
        let before = disk?.available ?? 0

        for target in chosen {
            cleaningTargetID = target.id
            do {
                let message = try await Cleaner.clean(target, useTrash: trash)
                addLog("\(target.name): \(message)", ok: true)
            } catch {
                addLog("\(target.name): \(error.localizedDescription)", ok: false)
            }
        }

        cleaningTargetID = nil
        selection.removeAll()
        isCleaning = false
        await scanAll()

        if let after = disk?.available, after > before {
            addLog("Итого на диске стало свободнее на \(Format.bytes(after - before))", ok: true)
        }
    }

    // MARK: - Проекты

    var filteredArtifacts: [ProjectArtifact] {
        artifacts.filter { $0.ageDays >= minAgeDays }
    }

    var selectedArtifacts: [ProjectArtifact] {
        filteredArtifacts.filter { projectSelection.contains($0.id) }
    }

    func scanProjects() async {
        isScanningProjects = true
        let root = projectRoot
        artifacts = await Task.detached(priority: .utility) {
            ProjectScanner.scan(root: root)
        }.value
        projectSelection = []
        didScanProjects = true
        isScanningProjects = false
    }

    func deleteSelectedArtifacts() async {
        let chosen = selectedArtifacts
        guard !chosen.isEmpty else { return }

        isCleaning = true
        let urls = chosen.map(\.url)
        let trash = useTrash

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Cleaner.remove(urls, useTrash: trash)
            }.value
            addLog("Проекты: удалено \(result.removed) папок, \(result.summary)", ok: result.errors.isEmpty)
            for error in result.errors { addLog(error, ok: false) }
        } catch {
            addLog("Проекты: \(error.localizedDescription)", ok: false)
        }

        let removed = Set(urls.filter { !FileManager.default.fileExists(atPath: $0.path) })
        artifacts.removeAll { removed.contains($0.url) }
        projectSelection.subtract(removed)
        disk = DiskInfo.current()
        isCleaning = false
    }

    private func addLog(_ text: String, ok: Bool) {
        log.insert(LogEntry(text: text, ok: ok), at: 0)
    }
}
