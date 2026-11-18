import Foundation
import Testing
@testable import DevCleaner

@Suite struct CatalogTests {
    @Test func idsAreUnique() {
        let ids = Catalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCommandNamesItsTool() {
        for target in Catalog.all where target.isCommand {
            #expect(target.requiredTool?.isEmpty == false, "\(target.id)")
        }
    }

    @Test func newTargetsExist() throws {
        let byID = Dictionary(uniqueKeysWithValues: Catalog.all.map { ($0.id, $0) })
        let caution = ["android.systemimages", "sim.runtimes", "rustup.toolchains", "codex.sessions", "whisper", "orbstack"]
        let safe = ["jetbrains.cache", "androidstudio.cache", "cargo.registry", "go.modcache", "go.build",
                    "maven", "nuget", "gemini.tmp", "claude.desktop.vm"]
        for id in caution { #expect(try #require(byID[id]).risk == .caution, "\(id)") }
        for id in safe { #expect(try #require(byID[id]).risk == .safe, "\(id)") }
        #expect(byID["go.modcache"]?.requiredTool == "go")
        #expect(byID["orbstack"]?.requiredTool == "orbctl")
        #expect(byID["sim.runtimes"]?.requiredTool == "xcrun")
    }

    @Test func noTargetPathIsProtected() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        for target in Catalog.all where !target.isCommand {
            for path in target.paths {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let relative = String(url.path.dropFirst(home.path.count))
                #expect(!Cleaner.protectedRelativePaths.contains(relative), "\(target.id): \(path)")
            }
        }
    }

    @Test func globExpandsToMatchingFolders() throws {
        let tmp = try TempDir()
        try tmp.dir("Google/AndroidStudio2024.1")
        try tmp.dir("Google/AndroidStudio2025.2")
        try tmp.dir("Google/Chrome")
        let urls = CleanupTarget.expand(tmp.url.path + "/Google/AndroidStudio*")
        #expect(urls.map(\.lastPathComponent) == ["AndroidStudio2024.1", "AndroidStudio2025.2"])
        #expect(CleanupTarget.expand(tmp.url.path + "/Missing/X*").isEmpty)
    }

    @MainActor @Test func categoryGroupsByRiskAndSize() throws {
        let name = "DevCleanerTests-\(UUID().uuidString)"
        let tmp = try TempDir()
        let store = CleanerStore(defaults: UserDefaults(suiteName: name)!,
                                 logFile: LogFile(url: tmp.url.appendingPathComponent("log.json")))
        let mobile = store.targets.filter { $0.category == .mobile }
        for target in mobile {
            store.measurements[target.id] = .init(size: 0, exists: false, installed: target.isCommand ? false : nil)
        }
        let safe = mobile.filter { $0.risk == .safe && !$0.isCommand }
        let caution = try #require(mobile.first { $0.risk == .caution && !$0.isCommand })
        store.measurements[safe[0].id] = .init(size: 10, exists: true)
        store.measurements[safe[1].id] = .init(size: 100, exists: true)
        store.measurements[safe[2].id] = .init(size: 0, exists: true)
        store.measurements[caution.id] = .init(size: 5, exists: true)

        let groups = store.groups(in: .mobile)
        #expect(groups.safe.map(\.id) == [safe[1].id, safe[0].id])
        #expect(groups.caution.map(\.id) == [caution.id])
        #expect(groups.inactive.count == mobile.count - 3)
        #expect(groups.inactive.contains { $0.id == safe[2].id })
    }
}
