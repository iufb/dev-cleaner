import Foundation

/// Ищет в папке с проектами тяжёлые артефакты сборки.
enum ProjectScanner {
    struct Rule: Sendable {
        let label: String
        /// Файлы-маркеры рядом с папкой. Пусто — подходит всегда.
        let markers: [String]
    }

    private static let gradleMarkers = [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
    ]

    static let rules: [String: Rule] = [
        "node_modules": Rule(label: "node_modules", markers: []),
        ".next": Rule(label: "Next.js", markers: []),
        ".nuxt": Rule(label: "Nuxt", markers: []),
        ".svelte-kit": Rule(label: "SvelteKit", markers: []),
        ".turbo": Rule(label: "Turborepo", markers: []),
        ".parcel-cache": Rule(label: "Parcel", markers: []),
        ".expo": Rule(label: "Expo", markers: []),
        ".angular": Rule(label: "Angular cache", markers: []),
        "Pods": Rule(label: "CocoaPods", markers: ["Podfile"]),
        ".build": Rule(label: "SwiftPM .build", markers: ["Package.swift"]),
        "DerivedData": Rule(label: "Xcode DerivedData", markers: []),
        ".gradle": Rule(label: "Gradle", markers: gradleMarkers),
        "build": Rule(label: "build (Gradle/Flutter)", markers: gradleMarkers + ["pubspec.yaml"]),
        ".dart_tool": Rule(label: "Dart tool", markers: ["pubspec.yaml"]),
        ".cxx": Rule(label: "Android NDK", markers: gradleMarkers),
        "target": Rule(label: "Rust/Maven target", markers: ["Cargo.toml", "pom.xml"]),
        ".venv": Rule(label: "Python venv", markers: []),
        "venv": Rule(label: "Python venv", markers: ["requirements.txt", "pyproject.toml"]),
    ]

    /// В эти папки не заходим: там нет проектов, а обход долгий.
    private static let skipped: Set<String> = [
        ".git", ".Trash", "Library", "Applications", ".cache", ".npm", ".pnpm-store",
        ".cargo", ".rustup", ".bun", ".ollama", ".docker", ".android", ".pub-cache",
        ".konan", ".lmstudio", ".vscode", ".cursor",
    ]

    static func scan(root: URL) -> [ProjectArtifact] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [ProjectArtifact] = []

        while let url = enumerator.nextObject() as? URL {
            guard
                let values = try? url.resourceValues(forKeys: Set(keys)),
                values.isDirectory == true,
                values.isSymbolicLink != true
            else { continue }

            let name = url.lastPathComponent

            if skipped.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard let rule = rules[name] else { continue }

            let project = url.deletingLastPathComponent()
            if !rule.markers.isEmpty {
                let hasMarker = rule.markers.contains {
                    fm.fileExists(atPath: project.appendingPathComponent($0).path)
                }
                guard hasMarker else { continue }
            }

            // Внутрь найденного артефакта не заходим (вложенные node_modules и т.п.).
            enumerator.skipDescendants()

            let touched = (try? project.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            found.append(ProjectArtifact(
                url: url,
                kind: rule.label,
                size: SizeCalculator.size(of: url),
                lastTouched: touched
            ))
        }

        return found.sorted { $0.size > $1.size }
    }
}
