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

@Suite struct CleanerContentsOnlyTests {
    @Test func unreadableFolderIsAnErrorNotZeroSuccess() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        let trash = try tmp.dir("home/.Trash")
        try tmp.file("home/.Trash/old.zip")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trash.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trash.path) }

        #expect(throws: Cleaner.CleanError.self) {
            try Cleaner.remove([trash], contentsOnly: true, useTrash: false, home: home)
        }
    }

    @Test func contentsOnlyKeepsFolder() throws {
        let tmp = try TempDir()
        let home = try tmp.dir("home")
        try tmp.file("home/.Trash/a")
        try tmp.file("home/.Trash/b/c")
        let result = try Cleaner.remove([home.appendingPathComponent(".Trash")], contentsOnly: true, useTrash: false, home: home)
        #expect(result.removed == 2)
        #expect(tmp.exists("home/.Trash"))
        #expect(!tmp.exists("home/.Trash/a"))
    }

    @Test func trashTargetIsAlwaysPermanent() throws {
        let trash = try #require(Catalog.all.first { $0.id == "trash" })
        #expect(trash.alwaysPermanent)
    }
}
