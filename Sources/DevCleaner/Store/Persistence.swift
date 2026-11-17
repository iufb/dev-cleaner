import Foundation

/// Журнал на диске: JSON в Application Support, только последние записи.
struct LogFile: Sendable {
    static let limit = 500

    let url: URL

    static var standard: LogFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LogFile(url: base.appendingPathComponent("DevCleaner/log.json"))
    }

    func load() -> [LogEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data)
        else { return [] }
        return Array(entries.prefix(Self.limit))
    }

    func save(_ entries: [LogEntry]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(entries.prefix(Self.limit)))
            try data.write(to: url, options: .atomic)
        } catch {
            // Журнал — не критичные данные: не смогли сохранить, работаем дальше.
        }
    }
}

/// Настройки, которые переживают перезапуск.
struct Settings {
    private enum Key {
        static let projectRoot = "projectRoot"
        static let minAgeDays = "minAgeDays"
        static let useTrash = "useTrash"
    }

    let defaults: UserDefaults

    var projectRoot: URL? {
        get {
            guard let path = defaults.string(forKey: Key.projectRoot) else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        nonmutating set { defaults.set(newValue?.path, forKey: Key.projectRoot) }
    }

    var minAgeDays: Int? {
        get { defaults.object(forKey: Key.minAgeDays) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Key.minAgeDays) }
    }

    var useTrash: Bool {
        get { defaults.bool(forKey: Key.useTrash) }
        nonmutating set { defaults.set(newValue, forKey: Key.useTrash) }
    }
}
