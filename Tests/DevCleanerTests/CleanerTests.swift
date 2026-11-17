import Foundation
import Testing
@testable import DevCleaner

@Suite struct CleanerTests {
    @Test(arguments: ["", "Library", ".ssh", "Library/Caches", ".claude"])
    func refusesProtectedPath(_ relative: String) throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        try tmp.file("home/Library/keep.txt")
        try tmp.file("home/.ssh/id_ed25519")
        try tmp.file("home/.claude/settings.json")
        try tmp.file("home/Library/Caches/keep")

        let target = relative.isEmpty ? home : home.appendingPathComponent(relative)
        #expect(throws: Cleaner.CleanError.self) {
            try Cleaner.remove([target], useTrash: false, home: home)
        }
        #expect(tmp.exists("home/Library/keep.txt"))
        #expect(tmp.exists("home/.ssh/id_ed25519"))
        #expect(tmp.exists("home/.claude/settings.json"))
        #expect(tmp.exists("home/Library/Caches/keep"))
    }

    @Test func refusesPathOutsideHome() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        let outside = try tmp.file("elsewhere/data.bin")

        do {
            _ = try Cleaner.remove([outside], useTrash: false, home: home)
            Issue.record("ожидалась ошибка")
        } catch let error as Cleaner.CleanError {
            #expect(error.localizedDescription.contains("защищён"))
        }
        #expect(tmp.exists("elsewhere/data.bin"))
    }

    @Test func refusesSymlinkEscapingHome() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        try tmp.file("elsewhere/data.bin")
        let link = home.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tmp.url.appendingPathComponent("elsewhere"))

        #expect(throws: Cleaner.CleanError.self) {
            try Cleaner.remove([link], useTrash: false, home: home)
        }
        #expect(tmp.exists("elsewhere/data.bin"))
    }

    @Test func removesCacheInsideHome() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        try tmp.file("home/.cache/tool/blob", bytes: 4096)

        let result = try Cleaner.remove([home.appendingPathComponent(".cache/tool")], useTrash: false, home: home)
        #expect(result.removed == 1)
        #expect(!tmp.exists("home/.cache/tool"))
        #expect(tmp.exists("home/.cache"))
    }
}
