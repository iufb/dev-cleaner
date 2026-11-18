import Foundation
import Testing
@testable import DevCleaner

@Suite struct SizeTests {
    @Test func hardLinksCountOnce() throws {
        let tmp = try TempDir()
        let original = try tmp.file("pkg/a.bin", bytes: 64 * 1024)
        try FileManager.default.linkItem(at: original, to: tmp.url.appendingPathComponent("pkg/b.bin"))
        let single = try tmp.file("single/a.bin", bytes: 64 * 1024)

        #expect(SizeCalculator.size(of: tmp.url.appendingPathComponent("pkg")) == SizeCalculator.size(of: single))
    }

    @Test func hardLinksAcrossUrlsCountOnce() throws {
        let tmp = try TempDir()
        let a = try tmp.file("x/a.bin", bytes: 64 * 1024)
        try tmp.dir("y")
        try FileManager.default.linkItem(at: a, to: tmp.url.appendingPathComponent("y/a.bin"))
        let both = SizeCalculator.size(of: [tmp.url.appendingPathComponent("x"), tmp.url.appendingPathComponent("y")])
        #expect(both == SizeCalculator.size(of: a))
    }

    @Test func cleanTitleWithoutSize() {
        #expect(Format.cleanTitle(count: 2, size: 0) == "Очистить (2)")
        #expect(!Format.cleanTitle(count: 2, size: 5_000_000).contains("Zero"))
    }

    @Test func trashResultSaysMoved() {
        var r = Cleaner.Result()
        r.movedToTrash = true
        r.size = 1_000_000
        #expect(r.summary.hasPrefix("перемещено в Корзину"))
        #expect(!r.summary.contains("освобождено"))
    }

    @Test func totalLineUsesFreeSpaceDelta() {
        #expect(Cleaner.totalLine(freeBefore: 100, freeAfter: 100, useTrash: true).contains("Корзины"))
        #expect(Cleaner.totalLine(freeBefore: 0, freeAfter: 2_000_000, useTrash: false).contains("свободнее"))
    }

    @Test func russianPlural() {
        #expect(Format.count(1, "папка", "папки", "папок") == "1 папка")
        #expect(Format.count(3, "папка", "папки", "папок") == "3 папки")
        #expect(Format.count(5, "папка", "папки", "папок") == "5 папок")
        #expect(Format.count(11, "папка", "папки", "папок") == "11 папок")
        #expect(Format.count(21, "папка", "папки", "папок") == "21 папка")
        #expect(Format.count(112, "папка", "папки", "папок") == "112 папок")
    }

    @Test func displayPathAbbreviatesHome() {
        #expect(Paths.display(URL(fileURLWithPath: "/Users/me/Projects"), home: "/Users/me") == "~/Projects")
        #expect(Paths.display(URL(fileURLWithPath: "/Users/me"), home: "/Users/me") == "~")
        #expect(Paths.display(URL(fileURLWithPath: "/Users/meow"), home: "/Users/me") == "/Users/meow")
    }

    @Test func relativeDateIsRussian() {
        let text = Format.relative(Date.now.addingTimeInterval(-3 * 86_400))
        #expect(text.contains("назад"))
    }
}
