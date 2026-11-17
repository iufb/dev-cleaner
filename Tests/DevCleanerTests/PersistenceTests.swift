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
