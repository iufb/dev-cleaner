import Foundation
@testable import DevCleaner

/// Временная папка, которая удаляется после теста.
final class TempDir {
    private(set) var url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevCleanerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        url = URL(fileURLWithPath: Paths.canonical(url), isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    /// Создаёт папку (с промежуточными) по относительному пути.
    @discardableResult
    func dir(_ path: String) throws -> URL {
        let u = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Создаёт файл по относительному пути.
    @discardableResult
    func file(_ path: String, bytes: Int = 16) throws -> URL {
        let u = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: bytes).write(to: u)
        return u
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path)
    }
}
