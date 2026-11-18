import Foundation
import Testing
@testable import DevCleaner

@MainActor
@Suite struct PersistenceTests {
    private func freshDefaults() -> UserDefaults {
        let name = "DevCleanerTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func logSurvivesRestartAndIsCapped() throws {
        let tmp = try TempDir()
        let file = LogFile(url: tmp.url.appendingPathComponent("log.json"))
        let defaults = freshDefaults()

        let first = CleanerStore(defaults: defaults, logFile: file)
        for i in 0..<(LogFile.limit + 20) { first.addLog("запись \(i)", ok: i % 2 == 0) }
        #expect(first.log.count == LogFile.limit)

        let second = CleanerStore(defaults: defaults, logFile: file)
        #expect(second.log == first.log)
        #expect(second.log.first?.text == "запись \(LogFile.limit + 19)")

        second.clearLog()
        #expect(CleanerStore(defaults: defaults, logFile: file).log.isEmpty)
    }

    @Test func settingsSurviveRestart() throws {
        let tmp = try TempDir()
        let file = LogFile(url: tmp.url.appendingPathComponent("log.json"))
        let defaults = freshDefaults()
        let root = try tmp.dir("work")

        let first = CleanerStore(defaults: defaults, logFile: file)
        first.projectRoot = root
        first.minAgeDays = 90
        first.useTrash = true

        let second = CleanerStore(defaults: defaults, logFile: file)
        #expect(second.projectRoot.path == root.path)
        #expect(second.minAgeDays == 90)
        #expect(second.useTrash)
    }

    @Test func partialFailureKeepsEveryErrorText() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        try tmp.file("home/cache/ok.bin")
        let locked = try tmp.dir("home/cache/locked")
        try tmp.file("home/cache/locked/inner")
        let parent = tmp.url.appendingPathComponent("home/cache")
        // Нельзя удалять из папки без права записи.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = try Cleaner.remove([parent.appendingPathComponent("ok.bin"), locked], useTrash: false, home: home)
        #expect(result.removed == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].hasPrefix("locked"))
    }
}

@MainActor
@Suite struct ProjectScanStoreTests {
    private func waitUntilDone(_ store: CleanerStore) async throws {
        for _ in 0..<500 where store.isScanningProjects {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.isScanningProjects)
    }

    @Test func rescanCancelsPreviousWithoutDuplicates() async throws {
        let tmp = try TempDir()
        for i in 0..<20 {
            try tmp.file("p\(i)/package.json")
            try tmp.file("p\(i)/node_modules/x/index.js")
        }
        let name = "DevCleanerTests-\(UUID().uuidString)"
        let store = CleanerStore(defaults: UserDefaults(suiteName: name)!,
                                 logFile: LogFile(url: tmp.url.appendingPathComponent("log.json")))
        store.projectRoot = tmp.url
        store.minAgeDays = 0

        store.scanProjects()
        store.scanProjects()
        try await waitUntilDone(store)

        #expect(store.artifacts.count == 20)
        #expect(Set(store.artifacts.map(\.url)).count == 20)
        #expect(store.projectSelection.isEmpty)
    }

    @Test func cancelKeepsWhatWasFound() async throws {
        let tmp = try TempDir()
        try tmp.file("p/package.json")
        try tmp.file("p/node_modules/x/index.js")
        let name = "DevCleanerTests-\(UUID().uuidString)"
        let store = CleanerStore(defaults: UserDefaults(suiteName: name)!,
                                 logFile: LogFile(url: tmp.url.appendingPathComponent("log.json")))
        store.projectRoot = tmp.url
        store.scanProjects()
        try await waitUntilDone(store)
        #expect(store.artifacts.count == 1)

        store.cancelProjectScan()
        #expect(store.artifacts.count == 1)
        #expect(!store.isScanningProjects)
    }

    @Test func logGroupsByRunAndKeepsLegacyEntries() throws {
        let tmp = try TempDir()
        let file = LogFile(url: tmp.url.appendingPathComponent("log.json"))
        // Запись старого формата: без runID и run.
        let legacy = #"[{"id":"\#(UUID().uuidString)","date":0,"text":"Старое","ok":true}]"#
        try Data(legacy.utf8).write(to: file.url)
        let old = file.load()
        #expect(old.count == 1)
        #expect(old[0].runID == nil)

        let first = UUID(), second = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        // Журнал хранится новыми записями вперёд.
        let log: [LogEntry] = [
            LogEntry(date: t0.addingTimeInterval(20), text: "Итого 2", ok: true, runID: second,
                     run: .init(scope: "Проекты", items: 1, useTrash: true, freed: 0)),
            LogEntry(date: t0.addingTimeInterval(19), text: "ошибка", ok: false, runID: second),
            LogEntry(date: t0.addingTimeInterval(11), text: "Итого 1", ok: true, runID: first,
                     run: .init(scope: "Кэши", items: 2, useTrash: false, freed: 100)),
            LogEntry(date: t0.addingTimeInterval(10), text: "шаг", ok: true, runID: first),
        ] + old

        let runs = LogRun.runs(from: log)
        #expect(runs.map(\.id) == [second, first, nil])
        #expect(runs[0].errors.count == 1)
        #expect(runs[1].entries.map(\.text) == ["шаг", "Итого 1"])
        #expect(runs[1].info?.freed == 100)
        #expect(runs[2].isLegacy)

        file.save(log)
        #expect(file.load() == log)
    }
}
