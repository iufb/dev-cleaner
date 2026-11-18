import Foundation

/// Одна очистка в журнале: все её записи и сводка.
struct LogRun: Identifiable, Equatable {
    /// `nil` — группа «Ранее» из записей старых версий без привязки к запуску.
    let id: UUID?
    /// Записи в порядке выполнения.
    let entries: [LogEntry]

    var info: LogEntry.RunInfo? { entries.lazy.compactMap(\.run).first }
    var date: Date { entries.map(\.date).max() ?? .distantPast }
    var errors: [LogEntry] { entries.filter { !$0.ok } }
    var isLegacy: Bool { id == nil }

    /// Журнал хранится новыми записями вперёд; запуски возвращаются так же, «Ранее» — в конце.
    static func runs(from log: [LogEntry]) -> [LogRun] {
        var order: [UUID] = []
        var byRun: [UUID: [LogEntry]] = [:]
        var legacy: [LogEntry] = []
        for entry in log {
            guard let runID = entry.runID else { legacy.append(entry); continue }
            if byRun[runID] == nil { order.append(runID) }
            byRun[runID, default: []].append(entry)
        }
        var runs = order.map { LogRun(id: $0, entries: byRun[$0, default: []].reversed()) }
        runs.sort { $0.date > $1.date }
        if !legacy.isEmpty { runs.append(LogRun(id: nil, entries: legacy.reversed())) }
        return runs
    }
}
