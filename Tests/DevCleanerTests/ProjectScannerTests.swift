import Foundation
import Testing
@testable import DevCleaner

@Suite struct ProjectScannerTests {
    private func found(_ tmp: TempDir, root: String = "home", home: String = "home") -> Set<String> {
        let rootURL = tmp.url.appendingPathComponent(root)
        let homeURL = tmp.url.appendingPathComponent(home)
        let prefix = tmp.url.path + "/"
        return Set(ProjectScanner.scan(root: rootURL, home: homeURL).map {
            String($0.url.path.dropFirst(prefix.count))
        })
    }

    @Test func ignoresGlobalPackagesAndFindsProjectNodeModules() throws {
        let tmp = try TempDir()
        // Глобальные пакеты nvm: рядом с node_modules нет package.json, и .nvm пропускается.
        try tmp.file("home/.nvm/versions/node/v22.0.0/lib/node_modules/typescript/package.json")
        // Расширение Raycast: внутри есть package.json, но .config пропускается целиком.
        try tmp.file("home/.config/raycast/extensions/abc/package.json")
        try tmp.file("home/.config/raycast/extensions/abc/node_modules/x/index.js")
        // Mason / nvm под ~/.local.
        try tmp.file("home/.local/share/nvim/mason/packages/tsserver/package.json")
        try tmp.file("home/.local/share/nvim/mason/packages/tsserver/node_modules/x/index.js")
        // Настоящий проект.
        try tmp.file("home/Projects/app/package.json")
        try tmp.file("home/Projects/app/node_modules/react/index.js")

        #expect(found(tmp) == ["home/Projects/app/node_modules"])
    }

    @Test func nodeModulesWithoutPackageJsonIsIgnored() throws {
        let tmp = try TempDir()
        try tmp.file("home/Projects/stray/node_modules/x/index.js")
        #expect(found(tmp).isEmpty)
    }

    @Test func homeExclusionsApplyByPathNotByName() throws {
        let tmp = try TempDir()
        // Library и .cache внутри проекта — обычные папки, их надо обходить.
        try tmp.file("home/Projects/app/Library/web/package.json")
        try tmp.file("home/Projects/app/Library/web/node_modules/x/index.js")
        try tmp.file("home/Projects/app/.cache/tool/package.json")
        try tmp.file("home/Projects/app/.cache/tool/node_modules/x/index.js")
        // А ~/Library пропускается.
        try tmp.file("home/Library/Application Support/foo/package.json")
        try tmp.file("home/Library/Application Support/foo/node_modules/x/index.js")

        #expect(found(tmp) == [
            "home/Projects/app/Library/web/node_modules",
            "home/Projects/app/.cache/tool/node_modules",
        ])
    }

    @Test func defaultRootPrefersProjectFolders() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        #expect(ProjectScanner.defaultRoot(home: home) == home)
        try tmp.dir("home/Code")
        #expect(ProjectScanner.defaultRoot(home: home).lastPathComponent == "Code")
        try tmp.dir("home/Developer")
        #expect(ProjectScanner.defaultRoot(home: home).lastPathComponent == "Developer")
        try tmp.dir("home/Projects")
        #expect(ProjectScanner.defaultRoot(home: home).lastPathComponent == "Projects")
    }
}

@Suite struct ProjectScannerStreamTests {
    @Test func streamYieldsSameAsSyncScan() async throws {
        let tmp = try TempDir()
        for i in 0..<12 {
            try tmp.file("home/Projects/p\(i)/package.json")
            try tmp.file("home/Projects/p\(i)/node_modules/x/index.js", bytes: 1000 * (i + 1))
        }
        let root = tmp.url.appendingPathComponent("home/Projects")
        let home = tmp.url.appendingPathComponent("home")

        var streamed: [ProjectArtifact] = []
        for await a in ProjectScanner.stream(root: root, home: home, concurrency: 3) { streamed.append(a) }
        let sync = ProjectScanner.scan(root: root, home: home)

        #expect(Set(streamed.map(\.url)) == Set(sync.map(\.url)))
        #expect(streamed.count == 12)
    }

    @Test func breakingOutStopsTheScan() async throws {
        let tmp = try TempDir()
        for i in 0..<30 {
            try tmp.file("home/Projects/p\(i)/package.json")
            try tmp.file("home/Projects/p\(i)/node_modules/x/index.js")
        }
        var count = 0
        for await _ in ProjectScanner.stream(root: tmp.url.appendingPathComponent("home/Projects"),
                                             home: tmp.url.appendingPathComponent("home")) {
            count += 1
            if count == 2 { break }
        }
        #expect(count == 2)
    }
}
