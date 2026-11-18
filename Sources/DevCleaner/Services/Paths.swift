import Foundation

enum Paths {
    /// Канонический путь без символических ссылок (через realpath(3)).
    /// В отличие от `resolvingSymlinksInPath`, не отрезает `/private`.
    /// Если пути нет, канонизируется ближайший существующий родитель.
    static func canonical(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        guard parent.path != path else { return path }
        return (canonical(parent) as NSString).appendingPathComponent(url.lastPathComponent)
    }

    /// Путь для показа человеку: домашняя папка заменяется на `~`.
    static func display(_ url: URL, home: String = NSHomeDirectory()) -> String {
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
