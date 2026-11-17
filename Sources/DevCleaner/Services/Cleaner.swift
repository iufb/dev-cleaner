import Foundation

enum Cleaner {
    enum CleanError: LocalizedError {
        case unsafePath(String)
        case nothingRemoved([String])

        var errorDescription: String? {
            switch self {
            case .unsafePath(let path):
                "отказ: путь \(path) защищён"
            case .nothingRemoved(let errors):
                "ничего не удалено. " + errors.prefix(3).joined(separator: "; ")
            }
        }
    }

    struct Result: Sendable {
        var freed: Int64 = 0
        var removed = 0
        var errors: [String] = []

        var summary: String {
            var text = "освобождено \(Format.bytes(freed))"
            if !errors.isEmpty { text += ", ошибок: \(errors.count)" }
            return text
        }
    }

    /// Папки внутри домашней, которые нельзя удалять ни при каких условиях.
    static let protectedRelativePaths: [String] = [
        "", "/Library", "/Documents", "/Desktop", "/Downloads", "/Movies", "/Music",
        "/Pictures", "/Developer", "/Library/Application Support", "/Library/Caches",
        "/Library/Developer", "/.ssh", "/.config", "/.claude",
    ]

    static func clean(_ target: CleanupTarget, useTrash: Bool) async throws -> String {
        switch target.action {
        case .command(let command):
            let output = try await Shell.run(command)
            let lastLine = output.split(separator: "\n").last.map(String.init) ?? ""
            return lastLine.isEmpty ? "выполнено" : lastLine

        case .delete(let contentsOnly):
            let urls = target.urls
            let result = try await Task.detached(priority: .userInitiated) {
                try remove(urls, contentsOnly: contentsOnly, useTrash: useTrash)
            }.value
            return result.summary
        }
    }

    /// - Parameter home: домашняя папка, внутри которой разрешено удалять.
    ///   Подменяется в тестах на временную папку.
    static func remove(
        _ urls: [URL],
        contentsOnly: Bool = false,
        useTrash: Bool,
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) throws -> Result {
        let fm = FileManager.default
        var items: [URL] = []

        for url in urls where fm.fileExists(atPath: url.path) {
            try assertSafe(url, home: home)
            if contentsOnly {
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                items.append(contentsOf: children)
            } else {
                items.append(url)
            }
        }

        var result = Result()
        for item in items {
            let size = SizeCalculator.size(of: item)
            do {
                if useTrash {
                    try fm.trashItem(at: item, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: item)
                }
                result.freed += size
                result.removed += 1
            } catch {
                result.errors.append("\(item.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if result.removed == 0 && !result.errors.isEmpty {
            throw CleanError.nothingRemoved(result.errors)
        }
        return result
    }

    /// Удаляем только внутри домашней папки и никогда — её «корневые» каталоги.
    static func assertSafe(_ url: URL, home: URL) throws {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let home = home.standardizedFileURL.resolvingSymlinksInPath().path
        let protected = Set(protectedRelativePaths.map { home + $0 })
        guard path.hasPrefix(home + "/"), !protected.contains(path) else {
            throw CleanError.unsafePath(path)
        }
    }
}
