import Foundation

/// Одна «цель» очистки: кэш, папка или команда.
struct CleanupTarget: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Hashable, Sendable {
        case mobile, web, agents, system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mobile: "Мобильная разработка"
            case .web: "Веб и Node"
            case .agents: "AI и агенты"
            case .system: "Система"
            }
        }

        var subtitle: String {
            switch self {
            case .mobile: "Xcode, симуляторы, CocoaPods, SwiftPM, Gradle, Android, Flutter"
            case .web: "npm, yarn, pnpm, bun, браузеры для тестов, Homebrew, Docker"
            case .agents: "Модели, Python-кэши, логи агентов и редакторов"
            case .system: "Логи, корзина, бэкапы iOS-устройств"
            }
        }

        var icon: String {
            switch self {
            case .mobile: "iphone"
            case .web: "globe"
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
        /// Выполнить shell-команду (через login-shell, чтобы был PATH из .zprofile).
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

    init(
        id: String,
        name: String,
        detail: String,
        category: Category,
        paths: [String],
        action: Action = .delete(contentsOnly: false),
        risk: Risk = .safe
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.category = category
        self.paths = paths
        self.action = action
        self.risk = risk
    }

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
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
