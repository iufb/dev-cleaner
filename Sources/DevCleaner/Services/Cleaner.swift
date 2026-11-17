import Foundation

enum Cleaner {
    enum CleanError: LocalizedError {
        /// Тексты отдельных ошибок, если они есть (для журнала).
        var details: [String] {
            if case .nothingRemoved(let errors) = self { return errors }
            return []
        }

        case unsafePath(String)
        case nothingRemoved([String])
        case unreadable(String, String)

        var errorDescription: String? {
            switch self {
            case .unsafePath(let path):
                "отказ: путь \(path) защищён"
            case .nothingRemoved(let errors):
                "ничего не удалено, ошибок: \(errors.count)"
            case .unreadable(let path, let reason):
                "не удалось прочитать \(path): \(reason). Возможно, нужен Полный доступ к диску"
            }
        }
    }

    struct Result: Sendable {
        /// Сколько занимало удалённое по подсчёту (каждый inode один раз).
        /// Реально освобождённое место может быть меньше: клоны APFS, ссылки на pnpm store.
        var size: Int64 = 0
        var removed = 0
        var errors: [String] = []
        var movedToTrash = false

        var summary: String {
            var text = movedToTrash
                ? "перемещено в Корзину: \(Format.bytes(size))"
                : "удалено \(Format.bytes(size))"
            if !errors.isEmpty { text += ", ошибок: \(errors.count)" }
            return text
        }
    }

    /// Итоговая строка журнала по изменению свободного места на томе.
    static func totalLine(freeBefore: Int64?, freeAfter: Int64?, useTrash: Bool) -> String {
        guard let freeBefore, let freeAfter else {
            return "Итого: не удалось узнать свободное место на диске"
        }
        let delta = freeAfter - freeBefore
        if delta > 0 {
            return "Итого на диске стало свободнее на \(Format.bytes(delta))"
        }
        return useTrash
            ? "Итого: свободное место не изменилось, оно освободится после очистки Корзины"
            : "Итого: свободное место на диске почти не изменилось"
    }

    /// Папки внутри домашней, которые нельзя удалять ни при каких условиях.
    static let protectedRelativePaths: [String] = [
        "", "/Library", "/Documents", "/Desktop", "/Downloads", "/Movies", "/Music",
        "/Pictures", "/Developer", "/Library/Application Support", "/Library/Caches",
        "/Library/Developer", "/.ssh", "/.config", "/.claude",
    ]

    /// Итог очистки одной цели: строка для журнала и тексты всех ошибок.
    struct Outcome: Sendable {
        var summary: String
        var errors: [String] = []
    }

    static func clean(_ target: CleanupTarget, useTrash: Bool) async throws -> Outcome {
        switch target.action {
        case .command(let command):
            let output = try await Shell.run(command)
            let lastLine = output.split(separator: "\n").last.map(String.init) ?? ""
            return Outcome(summary: lastLine.isEmpty ? "выполнено" : lastLine)

        case .delete(let contentsOnly):
            let urls = target.urls
            let trash = useTrash && !target.alwaysPermanent
            let result = try await Task.detached(priority: .userInitiated) {
                try remove(urls, contentsOnly: contentsOnly, useTrash: trash)
            }.value
            return Outcome(summary: result.summary, errors: result.errors)
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
                do {
                    items.append(contentsOf: try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))
                } catch {
                    throw CleanError.unreadable(url.path, error.localizedDescription)
                }
            } else {
                items.append(url)
            }
        }

        var result = Result()
        result.movedToTrash = useTrash
        var seen = SizeCalculator.Seen()
        for item in items {
            let size = SizeCalculator.size(of: item, seen: &seen)
            do {
                if useTrash {
                    try fm.trashItem(at: item, resultingItemURL: nil)
                } else {
                    try fm.removeItem(at: item)
                }
                result.size += size
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
        let path = Paths.canonical(url)
        let home = Paths.canonical(home)
        let protected = Set(protectedRelativePaths.map { home + $0 })
        guard path.hasPrefix(home + "/"), !protected.contains(path) else {
            throw CleanError.unsafePath(path)
        }
    }
}
