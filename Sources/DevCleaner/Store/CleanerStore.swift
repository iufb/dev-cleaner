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
    var useTrash = false {
        didSet { settings.useTrash = useTrash }
    }
    var disk: DiskInfo? = DiskInfo.current()
    var hasFullDiskAccess = true
    var log: [LogEntry] = [] {
        didSet { logFile.save(log) }
    }

    // MARK: Проекты

    var projectRoot: URL = ProjectScanner.defaultRoot() {
        didSet { settings.projectRoot = projectRoot }
    }
    var artifacts: [ProjectArtifact] = []
    var projectSelection: Set<URL> = []
    var isScanningProjects = false
    var didScanProjects = false
    var minAgeDays = 30 {
        didSet { settings.minAgeDays = minAgeDays }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanGeneration: UUID?
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let logFile: LogFile

    init(defaults: UserDefaults = .standard, logFile: LogFile = .standard) {
        self.settings = Settings(defaults: defaults)
        self.logFile = logFile
        if let root = settings.projectRoot { projectRoot = root }
        if let days = settings.minAgeDays { minAgeDays = days }
        useTrash = settings.useTrash
        log = logFile.load()
    }

    var isBusy: Bool { isCleaning || !scanning.isEmpty || isScanningProjects }
    /// Идёт подсчёт или очистка кэшей (поиск проектов им не мешает).
    var isCacheBusy: Bool { isCleaning || !scanning.isEmpty }

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
                    let size = SizeCalculator.size(of: existing)
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
        hasFullDiskAccess = await Task.detached { FullDiskAccess.isGranted() }.value
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

    /// Что можно освободить без риска: ровно то, что выбирает `selectSafe()`.
    var safeTargets: [CleanupTarget] {
        targets.filter { $0.risk == .safe && size(of: $0) > 0 }
    }

    /// «Осторожные» цели, которые реально что-то занимают.
    var cautionTargets: [CleanupTarget] {
        targets.filter { $0.risk == .caution && size(of: $0) > 0 }
    }

    struct TargetGroups {
        var safe: [CleanupTarget] = []
        var caution: [CleanupTarget] = []
        /// Пустые, отсутствующие и неустановленные: показываются свёрнутыми.
        var inactive: [CleanupTarget] = []
    }

    /// Есть ли что чистить: папка не пустая или это установленная команда без путей для подсчёта.
    func isActive(_ target: CleanupTarget) -> Bool {
        guard isAvailable(target) else { return false }
        if target.isCommand && target.paths.isEmpty { return true }
        return size(of: target) > 0
    }

    /// Цели категории по группам риска; внутри группы по размеру, команды без размера в конце.
    func groups(in category: CleanupTarget.Category) -> TargetGroups {
        var result = TargetGroups()
        let items = targets.enumerated()
            .filter { $0.element.category == category }
            .sorted { lhs, rhs in
                let (a, b) = (size(of: lhs.element), size(of: rhs.element))
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
        for target in items {
            if !isActive(target) {
                result.inactive.append(target)
            } else if target.risk == .safe {
                result.safe.append(target)
            } else {
                result.caution.append(target)
            }
        }
        return result
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
        for target in safeTargets where category == nil || target.category == category {
            selection.insert(target.id)
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
        let before = DiskInfo.freeBytes()

        for target in chosen {
            cleaningTargetID = target.id
            do {
                let outcome = try await Cleaner.clean(target, useTrash: trash)
                addLog("\(target.name): \(outcome.summary)", ok: outcome.errors.isEmpty)
                for error in outcome.errors { addLog("\(target.name): \(error)", ok: false) }
            } catch {
                logFailure(error, prefix: target.name)
            }
        }

        cleaningTargetID = nil
        selection.removeAll()
        isCleaning = false
        let after = DiskInfo.freeBytes()
        addLog(Cleaner.totalLine(freeBefore: before, freeAfter: after, useTrash: trash), ok: true)
        await scanAll()
    }

    // MARK: - Проекты

    var filteredArtifacts: [ProjectArtifact] {
        artifacts.filter { $0.ageDays >= minAgeDays }.sorted { $0.size > $1.size }
    }

    var selectedArtifacts: [ProjectArtifact] {
        filteredArtifacts.filter { projectSelection.contains($0.id) }
    }

    var foundSize: Int64 { artifacts.reduce(0) { $0 + $1.size } }

    /// Запускает поиск артефактов. Предыдущий поиск, если он идёт, отменяется.
    func scanProjects() {
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        artifacts = []
        projectSelection = []
        didScanProjects = true
        isScanningProjects = true

        let root = projectRoot
        scanTask = Task { [weak self] in
            for await artifact in ProjectScanner.stream(root: root) {
                guard let self, self.scanGeneration == generation else { return }
                self.artifacts.append(artifact)
            }
            guard let self, self.scanGeneration == generation else { return }
            self.isScanningProjects = false
            self.scanTask = nil
        }
    }

    /// Останавливает поиск. Уже найденное остаётся в таблице.
    func cancelProjectScan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration = nil
        isScanningProjects = false
    }

    func setProjectRoot(_ url: URL) {
        cancelProjectScan()
        projectRoot = url
        didScanProjects = false
        artifacts = []
        projectSelection = []
    }

    func deleteSelectedArtifacts() async {
        let chosen = selectedArtifacts
        guard !chosen.isEmpty else { return }

        isCleaning = true
        let urls = chosen.map(\.url)
        let trash = useTrash
        let before = DiskInfo.freeBytes()

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Cleaner.remove(urls, useTrash: trash)
            }.value
            addLog("Проекты: \(result.removed) папок, \(result.summary)", ok: result.errors.isEmpty)
            for error in result.errors { addLog("Проекты: \(error)", ok: false) }
        } catch {
            logFailure(error, prefix: "Проекты")
        }

        addLog(Cleaner.totalLine(freeBefore: before, freeAfter: DiskInfo.freeBytes(), useTrash: trash), ok: true)

        let removed = Set(urls.filter { !FileManager.default.fileExists(atPath: $0.path) })
        artifacts.removeAll { removed.contains($0.url) }
        projectSelection.subtract(removed)
        disk = DiskInfo.current()
        isCleaning = false
    }

    private func logFailure(_ error: Error, prefix: String) {
        addLog("\(prefix): \(error.localizedDescription)", ok: false)
        for detail in (error as? Cleaner.CleanError)?.details ?? [] {
            addLog("\(prefix): \(detail)", ok: false)
        }
    }

    func addLog(_ text: String, ok: Bool) {
        log.insert(LogEntry(text: text, ok: ok), at: 0)
        if log.count > LogFile.limit { log.removeLast(log.count - LogFile.limit) }
    }

    func clearLog() {
        log.removeAll()
    }
}
