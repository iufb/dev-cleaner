import Foundation

/// Артефакт сборки внутри конкретного проекта: node_modules, Pods, build, target…
struct ProjectArtifact: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let kind: String
    let size: Int64
    /// Когда в последний раз менялась папка проекта (приблизительная «активность»).
    let lastTouched: Date

    var projectURL: URL { url.deletingLastPathComponent() }
    var projectName: String { projectURL.lastPathComponent }

    var ageDays: Int {
        Calendar.current.dateComponents([.day], from: lastTouched, to: .now).day ?? 0
    }
}

struct DiskInfo: Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { total - available }
    var freeFraction: Double { total > 0 ? Double(available) / Double(total) : 0 }

    static func current() -> DiskInfo? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskInfo(total: Int64(total), available: available)
    }

    /// Свободное место на томе прямо сейчас, без учёта purgeable.
    /// По его изменению считается, сколько на самом деле освободила очистка.
    static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let free = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        else { return nil }
        return Int64(free)
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    let ok: Bool
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// «Очистить 3,2 ГБ», а если размер неизвестен (только команды) — «Очистить (2)».
    static func cleanTitle(count: Int, size: Int64) -> String {
        size > 0 ? "Очистить \(bytes(size))" : "Очистить (\(count))"
    }
}
