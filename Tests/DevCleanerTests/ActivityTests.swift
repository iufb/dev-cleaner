import Foundation
import Testing
@testable import DevCleaner

@Suite struct ActivityTests {
    private let old = Date(timeIntervalSinceNow: -400 * 86_400)

    private func age(_ tmp: TempDir, _ paths: [String]) throws {
        // Сначала файлы, потом папки от глубоких к корню, чтобы создание не обновило даты.
        for path in paths.sorted(by: { $0.count > $1.count }) {
            try FileManager.default.setAttributes([.modificationDate: old],
                                                  ofItemAtPath: tmp.url.appendingPathComponent(path).path)
        }
    }

    @Test func freshSourceFileMakesProjectActive() throws {
        let tmp = try TempDir()
        try tmp.file("app/package.json")
        try tmp.file("app/node_modules/x/index.js")
        try tmp.dir("app/old-folder")
        try tmp.file("app/src/main.ts")
        try age(tmp, ["app/package.json", "app/node_modules/x/index.js", "app/node_modules/x",
                      "app/node_modules", "app/old-folder", "app"])

        let found = ProjectScanner.scan(root: tmp.url, home: tmp.url.appendingPathComponent("nohome"))
        let artifact = try #require(found.first)
        #expect(artifact.ageDays == 0)
    }

    @Test func freshFilesInsideArtifactsAndGitDoNotCount() throws {
        let tmp = try TempDir()
        try tmp.file("app/package.json")
        try tmp.file("app/src/main.ts")
        try tmp.file("app/node_modules/x/index.js")   // свежий, но артефакт
        try tmp.file("app/.git/index")                // свежий, но git
        try tmp.file("app/.next/cache/blob")          // свежий, но артефакт
        try age(tmp, ["app/package.json", "app/src/main.ts", "app/src", "app"])

        let date = ProjectScanner.lastActivity(of: tmp.url.appendingPathComponent("app"))
        #expect(abs(date.timeIntervalSince(old)) < 2)
    }

    @Test func walkIsBounded() throws {
        let tmp = try TempDir()
        try tmp.file("app/a/b/c/d/e/f/g/h/deep.txt")
        try age(tmp, ["app/a/b/c/d/e/f/g/h", "app/a/b/c/d/e/f/g", "app/a/b/c/d/e/f", "app/a/b/c/d/e",
                      "app/a/b/c/d", "app/a/b/c", "app/a/b", "app/a", "app"])
        // Файл глубже лимита не учитывается.
        let date = ProjectScanner.lastActivity(of: tmp.url.appendingPathComponent("app"), maxDepth: 3)
        #expect(date < Date(timeIntervalSinceNow: -86_400))
    }
}
