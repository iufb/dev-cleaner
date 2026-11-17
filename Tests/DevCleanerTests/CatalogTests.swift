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
}
