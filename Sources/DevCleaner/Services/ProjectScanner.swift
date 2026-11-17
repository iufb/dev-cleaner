import Foundation

/// Ищет в папке с проектами тяжёлые артефакты сборки.
enum ProjectScanner {
    struct Rule: Sendable {
        let label: String
        /// Путь артефакта относительно проекта: `node_modules`, `.yarn/cache`.
        /// Последний компонент может заканчиваться на `*` (`cmake-build-*`).
        let pattern: String
        /// Файлы-маркеры в папке проекта. Поддерживается `*.ext`.
        /// Хотя бы один должен быть, иначе это не проект нужного типа.
        let markers: [String]

        init(_ label: String, _ pattern: String, markers: [String]) {
            precondition(!markers.isEmpty, "у правила \(pattern) должен быть маркер")
            self.label = label
            self.pattern = pattern
            self.markers = markers
        }

        var components: [String] { pattern.split(separator: "/").map(String.init) }

        /// Если `url` — артефакт этого правила, возвращает папку проекта.
        func project(for url: URL) -> URL? {
            let parts = components
            let tail = url.pathComponents.suffix(parts.count)
            guard tail.count == parts.count else { return nil }
            for (name, pattern) in zip(tail, parts) {
                if pattern.hasSuffix("*") {
                    guard name.hasPrefix(pattern.dropLast()) else { return nil }
                } else if name != pattern {
                    return nil
                }
            }
            var project = url
            for _ in parts { project.deleteLastPathComponent() }
            return project
        }
    }

    private static let gradleMarkers = [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
    ]

    static let rules: [Rule] = [
        Rule("node_modules", "node_modules", markers: ["package.json"]),
        Rule("Next.js", ".next", markers: ["package.json"]),
        Rule("Nuxt", ".nuxt", markers: ["package.json"]),
        Rule("SvelteKit", ".svelte-kit", markers: ["package.json"]),
        Rule("Turborepo", ".turbo", markers: ["package.json", "turbo.json"]),
        Rule("Parcel", ".parcel-cache", markers: ["package.json"]),
        Rule("Expo", ".expo", markers: ["package.json", "app.json"]),
        Rule("Angular cache", ".angular", markers: ["angular.json"]),
        Rule("CocoaPods", "Pods", markers: ["Podfile"]),
        Rule("SwiftPM .build", ".build", markers: ["Package.swift"]),
        Rule("Xcode DerivedData", "DerivedData", markers: ["*.xcodeproj", "*.xcworkspace", "Package.swift"]),
        Rule("Gradle", ".gradle", markers: gradleMarkers),
        Rule("build (Gradle/Flutter)", "build", markers: gradleMarkers + ["pubspec.yaml"]),
        Rule("Dart tool", ".dart_tool", markers: ["pubspec.yaml"]),
        Rule("Android NDK", ".cxx", markers: gradleMarkers),
        Rule("Rust/Maven target", "target", markers: ["Cargo.toml", "pom.xml"]),
        Rule("Python venv", ".venv", markers: pythonMarkers),
        Rule("Python venv", "venv", markers: pythonMarkers),
    ]

    static let pythonMarkers = [
        "pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile", "uv.lock", "poetry.lock",
    ]

    /// Имена папок, в которые не заходим нигде.
    private static let skippedNames: Set<String> = [".git", ".hg", ".svn"]

    /// Папки инструментов и данных в домашней папке. Там нет проектов, зато есть
    /// глобальные пакеты (`~/.nvm/.../node_modules`, расширения Raycast), удаление
    /// которых ломает CLI, LSP и расширения.
    static let skippedInHome: [String] = [
        "Library", "Applications", ".Trash", ".cache", ".local", ".config",
        ".npm", ".pnpm-store", ".yarn", ".bun", ".deno", ".nvm", ".volta", ".fnm", ".nodenv",
        ".cargo", ".rustup", "go", ".m2", ".gradle", ".nuget", ".dotnet", ".pyenv", ".rbenv",
        ".gem", ".sdkman", ".pub-cache", ".konan", ".android", ".docker", ".orbstack", "OrbStack",
        ".ollama", ".lmstudio", ".vscode", ".cursor", ".claude", ".codex", ".gemini",
        ".oh-my-zsh", ".tmux", ".zsh", ".vim",
    ]

    /// Папка поиска по умолчанию: первая существующая из привычных папок с проектами.
    static func defaultRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        for name in ["Projects", "Developer", "Code"] {
            let url = home.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return home
    }

    /// Синхронный поиск: все артефакты, отсортированные по размеру.
    static func scan(
        root: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ProjectArtifact] {
        var found: [ProjectArtifact] = []
        var candidates = Candidates(root: root, home: home)
        while let candidate = candidates.next() {
            found.append(artifact(for: candidate))
        }
        return found.sorted { $0.size > $1.size }
    }

    /// Поиск с выдачей по ходу. Размеры считаются параллельно (до `concurrency` сразу).
    /// Прекращение чтения потока или отмена задачи-читателя останавливает обход.
    static func stream(
        root: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        concurrency: Int = 6
    ) -> AsyncStream<ProjectArtifact> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                var candidates = Candidates(root: root, home: home)
                await withTaskGroup(of: ProjectArtifact?.self) { group in
                    var running = 0
                    while !Task.isCancelled, let candidate = candidates.next() {
                        if running >= concurrency, let done = await group.next() {
                            running -= 1
                            if let done { continuation.yield(done) }
                        }
                        group.addTask { Task.isCancelled ? nil : artifact(for: candidate) }
                        running += 1
                    }
                    for await done in group {
                        if let done, !Task.isCancelled { continuation.yield(done) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func artifact(for candidate: Candidate) -> ProjectArtifact {
        ProjectArtifact(
            url: candidate.url,
            kind: candidate.rule.label,
            size: SizeCalculator.size(of: candidate.url),
            lastTouched: lastActivity(of: candidate.project)
        )
    }

    /// Имена папок, которые не считаются работой над проектом: артефакты и VCS.
    private static let inactiveNames: Set<String> = {
        var names = skippedNames
        for rule in rules {
            if let first = rule.components.first, !first.hasSuffix("*") { names.insert(first) }
        }
        return names
    }()

    /// Дата изменения самого свежего файла проекта, без артефактов и `.git`.
    /// Обход ограничен глубиной и числом файлов, чтобы не тормозить поиск.
    static func lastActivity(of project: URL, maxDepth: Int = 6, maxFiles: Int = 5000) -> Date {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        let ownDate = (try? project.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let enumerator = FileManager.default.enumerator(
            at: project,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return ownDate ?? .distantPast }

        var latest: Date?
        var files = 0
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true {
                if inactiveNames.contains(url.lastPathComponent)
                    || prefixRules.contains(where: { url.lastPathComponent.hasPrefix($0) })
                    || enumerator.level >= maxDepth {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, let date = values.contentModificationDate else { continue }
            if latest.map({ date > $0 }) ?? true { latest = date }
            files += 1
            if files >= maxFiles || Task.isCancelled { break }
        }
        return latest ?? ownDate ?? .distantPast
    }

    private static let prefixRules: [String] = rules.compactMap { rule in
        guard let first = rule.components.first, first.hasSuffix("*") else { return nil }
        return String(first.dropLast())
    }

    struct Candidate: Sendable {
        let url: URL
        let project: URL
        let rule: Rule
    }

    /// Ленивый обход дерева: отдаёт найденные артефакты по одному.
    struct Candidates: IteratorProtocol {
        private let enumerator: FileManager.DirectoryEnumerator?
        private let skippedPaths: Set<String>
        private let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        init(root: URL, home: URL) {
            let home = URL(fileURLWithPath: Paths.canonical(home))
            skippedPaths = Set(ProjectScanner.skippedInHome.map { home.appendingPathComponent($0).path })
            enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: Paths.canonical(root), isDirectory: true),
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
        }

        mutating func next() -> Candidate? {
            guard let enumerator else { return nil }
            while let url = enumerator.nextObject() as? URL {
                guard
                    let values = try? url.resourceValues(forKeys: Set(keys)),
                    values.isDirectory == true,
                    values.isSymbolicLink != true
                else { continue }

                if ProjectScanner.skippedNames.contains(url.lastPathComponent)
                    || skippedPaths.contains(url.path) {
                    enumerator.skipDescendants()
                    continue
                }

                for rule in ProjectScanner.rules {
                    guard let project = rule.project(for: url),
                          ProjectScanner.hasMarker(rule.markers, in: project)
                    else { continue }
                    // Внутрь найденного артефакта не заходим (вложенные node_modules и т.п.).
                    enumerator.skipDescendants()
                    return Candidate(url: url, project: project, rule: rule)
                }
            }
            return nil
        }
    }

    static func hasMarker(_ markers: [String], in folder: URL) -> Bool {
        let fm = FileManager.default
        var listing: [String]?
        for marker in markers {
            if marker.hasPrefix("*") {
                if listing == nil { listing = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] }
                let suffix = marker.dropFirst()
                if listing!.contains(where: { $0.hasSuffix(suffix) }) { return true }
            } else if fm.fileExists(atPath: folder.appendingPathComponent(marker).path) {
                return true
            }
        }
        return false
    }
}
