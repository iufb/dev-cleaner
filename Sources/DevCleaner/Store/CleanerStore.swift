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
    /// Ход текущей очистки: показывается в окне подтверждения.
    var cleanProgress: CleanProgress?
    /// Итог последней очистки: показывается в окне подтверждения после её конца.
    var lastReport: CleanReport?
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
    /// Показывать только эти типы артефактов; пусто — все.
    var kindFilter: Set<String> = []
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

    struct CleanProgress: Equatable {
        var done: Int
        var total: Int
        var current: String
    }

    struct CleanReport: Equatable {
        /// Насколько выросло свободное место на диске; `nil`, если узнать не удалось.
        var freed: Int64?
        var useTrash: Bool
        var errors: [String]
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
        lastReport = nil
        let trash = useTrash
        let before = DiskInfo.freeBytes()
        var errors: [String] = []

        for (index, target) in chosen.enumerated() {
            cleaningTargetID = target.id
            cleanProgress = CleanProgress(done: index, total: chosen.count, current: target.name)
            do {
                let outcome = try await Cleaner.clean(target, useTrash: trash)
                addLog("\(target.name): \(outcome.summary)", ok: outcome.errors.isEmpty)
                for error in outcome.errors { addLog("\(target.name): \(error)", ok: false) }
                errors += outcome.errors.map { "\(target.name): \($0)" }
            } catch {
                errors += logFailure(error, prefix: target.name)
            }
        }

        cleaningTargetID = nil
        cleanProgress = nil
        selection.removeAll()
        let after = DiskInfo.freeBytes()
        addLog(Cleaner.totalLine(freeBefore: before, freeAfter: after, useTrash: trash), ok: true)
        lastReport = CleanReport(freed: Self.freed(before, after), useTrash: trash, errors: errors)
        isCleaning = false
        await scanAll()
    }

    // MARK: - Проекты

    var filteredArtifacts: [ProjectArtifact] {
        ageFilteredArtifacts
            .filter { kindFilter.isEmpty || kindFilter.contains($0.kind) }
            .sorted { $0.size > $1.size }
    }

    private var ageFilteredArtifacts: [ProjectArtifact] {
        artifacts.filter { $0.ageDays >= minAgeDays }
    }

    /// Типы артефактов, которые есть среди найденного (с учётом возраста), крупные первыми.
    var artifactKinds: [String] {
        var sizes: [String: Int64] = [:]
        for artifact in ageFilteredArtifacts { sizes[artifact.kind, default: 0] += artifact.size }
        return sizes.keys.sorted { a, b in
            let (sa, sb) = (sizes[a] ?? 0, sizes[b] ?? 0)
            return sa != sb ? sa > sb : a < b
        }
    }

    enum ArtifactGrouping: Hashable { case project, kind }

    struct ArtifactGroup: Identifiable {
        let id: String
        let title: String
        /// Папка проекта; для группировки по типу — `nil`.
        let projectURL: URL?
        let items: [ProjectArtifact]
        var size: Int64 { items.reduce(0) { $0 + $1.size } }
        var lastTouched: Date { items.map(\.lastTouched).max() ?? .distantPast }
    }

    /// Найденное с учётом фильтров, сгруппированное по проекту или по типу. Группы и строки — по размеру.
    func artifactGroups(by grouping: ArtifactGrouping) -> [ArtifactGroup] {
        let items = filteredArtifacts
        let groups: [ArtifactGroup]
        switch grouping {
        case .project:
            groups = Dictionary(grouping: items, by: \.projectURL).map { url, items in
                ArtifactGroup(id: url.path, title: url.lastPathComponent, projectURL: url, items: items)
            }
        case .kind:
            groups = Dictionary(grouping: items, by: \.kind).map { kind, items in
                ArtifactGroup(id: kind, title: kind, projectURL: nil, items: items)
            }
        }
        return groups.sorted { $0.size != $1.size ? $0.size > $1.size : $0.id < $1.id }
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
        lastReport = nil
        let urls = chosen.map(\.url)
        let trash = useTrash
        let before = DiskInfo.freeBytes()
        var errors: [String] = []
        cleanProgress = CleanProgress(done: 0, total: 1, current: Format.count(urls.count, "папка", "папки", "папок"))

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Cleaner.remove(urls, useTrash: trash)
            }.value
            addLog("Проекты: \(result.removed) папок, \(result.summary)", ok: result.errors.isEmpty)
            for error in result.errors { addLog("Проекты: \(error)", ok: false) }
            errors += result.errors
        } catch {
            errors += logFailure(error, prefix: "Проекты")
        }

        let after = DiskInfo.freeBytes()
        addLog(Cleaner.totalLine(freeBefore: before, freeAfter: after, useTrash: trash), ok: true)
        cleanProgress = nil
        lastReport = CleanReport(freed: Self.freed(before, after), useTrash: trash, errors: errors)

        let removed = Set(urls.filter { !FileManager.default.fileExists(atPath: $0.path) })
        artifacts.removeAll { removed.contains($0.url) }
        projectSelection.subtract(removed)
        disk = DiskInfo.current()
        isCleaning = false
    }

    /// Пишет ошибку в журнал и возвращает её строки для итога очистки.
    @discardableResult
    private func logFailure(_ error: Error, prefix: String) -> [String] {
        let lines = ["\(prefix): \(error.localizedDescription)"]
            + ((error as? Cleaner.CleanError)?.details ?? []).map { "\(prefix): \($0)" }
        for line in lines { addLog(line, ok: false) }
        return lines
    }

    static func freed(_ before: Int64?, _ after: Int64?) -> Int64? {
        guard let before, let after else { return nil }
        return max(0, after - before)
    }

    func addLog(_ text: String, ok: Bool) {
        log.insert(LogEntry(text: text, ok: ok), at: 0)
        if log.count > LogFile.limit { log.removeLast(log.count - LogFile.limit) }
    }

    func clearLog() {
        log.removeAll()
    }
}
