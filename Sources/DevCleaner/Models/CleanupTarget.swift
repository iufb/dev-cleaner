import Foundation
import SwiftUI

/// Одна «цель» очистки: кэш, папка или команда.
struct CleanupTarget: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Hashable, Sendable {
        case mobile, web, languages, agents, system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mobile: "Мобильная разработка"
            case .web: "Веб и Node"
            case .languages: "Другие языки"
            case .agents: "AI и агенты"
            case .system: "Система"
            }
        }

        var subtitle: String {
            switch self {
            case .mobile: "Xcode, симуляторы, CocoaPods, SwiftPM, Gradle, Android, Flutter"
            case .web: "npm, yarn, pnpm, bun, браузеры для тестов, Homebrew, Docker, OrbStack"
            case .languages: "Rust, Go, Maven, NuGet"
            case .agents: "Модели, Python-кэши, логи агентов и редакторов"
            case .system: "Логи, корзина, бэкапы iOS-устройств"
            }
        }

        /// Цвет категории в составной полосе и легенде сводки.
        var color: Color {
            switch self {
            case .mobile: .blue
            case .web: .green
            case .languages: .pink
            case .agents: .purple
            case .system: .gray
            }
        }

        var icon: String {
            switch self {
            case .mobile: "iphone"
            case .web: "globe"
            case .languages: "chevron.left.forwardslash.chevron.right"
            case .agents: "cpu"
            case .system: "gearshape"
            }
        }
    }

    enum Risk: Hashable, Sendable {
        /// Восстановится само (сборка/менеджер пакетов скачает заново).
        case safe
        /// Удалятся данные, которые долго качать или которые нельзя восстановить.
        case caution
    }

    enum Action: Hashable, Sendable {
        /// Удалить папки целиком (или только их содержимое).
        case delete(contentsOnly: Bool)
        /// Выполнить shell-команду с PATH из login shell пользователя.
        case command(String)
    }

    let id: String
    let name: String
    let detail: String
    let category: Category
    /// Пути с `~`. Для команд используются только для подсчёта размера.
    let paths: [String]
    let action: Action
    let risk: Risk
    /// Программа, без которой команда не сработает. По умолчанию — первое слово команды.
    let requiredTool: String?
    /// Всегда удалять безвозвратно, даже в режиме «В Корзину» (сама Корзина).
    let alwaysPermanent: Bool

    init(
        id: String,
        name: String,
        detail: String,
        category: Category,
        paths: [String],
        action: Action = .delete(contentsOnly: false),
        risk: Risk = .safe,
        requires tool: String? = nil,
        alwaysPermanent: Bool = false
    ) {
        self.alwaysPermanent = alwaysPermanent
        self.id = id
        self.name = name
        self.detail = detail
        self.category = category
        self.paths = paths
        self.action = action
        self.risk = risk
        if case .command(let command) = action {
            self.requiredTool = tool ?? command.split(separator: " ").first.map(String.init)
        } else {
            self.requiredTool = tool
        }
    }

    /// Пути с раскрытой `~`. Последний компонент может быть шаблоном `Prefix*`:
    /// тогда берутся все подходящие папки рядом (`AndroidStudio2024.1`, `AndroidStudio2025.1`).
    var urls: [URL] {
        paths.flatMap { Self.expand($0) }
    }

    static func expand(_ path: String) -> [URL] {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let last = url.lastPathComponent
        guard last.hasSuffix("*") else { return [url] }
        let parent = url.deletingLastPathComponent()
        let prefix = last.dropLast()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { parent.appendingPathComponent($0) }
    }

    var isCommand: Bool {
        if case .command = action { return true }
        return false
    }

    var displayLocation: String {
        switch action {
        case .command(let cmd): "$ \(cmd)"
        case .delete: paths.joined(separator: "  ·  ")
        }
    }
}
