import SwiftUI

/// Журнал по запускам очистки, сгруппированным по дням.
struct LogView: View {
    @Environment(CleanerStore.self) private var store
    @State private var errorsOnly = false
    /// Раскрытые и свёрнутые вручную; без записи действует правило по умолчанию.
    @State private var toggled: [String: Bool] = [:]

    private var runs: [LogRun] {
        let all = LogRun.runs(from: store.log)
        return errorsOnly ? all.filter { !$0.errors.isEmpty } : all
    }

    var body: some View {
        Group {
            if store.log.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "list.bullet.rectangle",
                                       description: Text("Здесь появится каждая очистка: что удалено, сколько освободилось и что не получилось."))
            } else if runs.isEmpty {
                ContentUnavailableView("Ошибок не было", systemImage: "checkmark.circle",
                                       description: Text("Все очистки прошли без ошибок."))
            } else {
                list
            }
        }
        .navigationTitle("Журнал")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $errorsOnly) {
                    Label("Только с ошибками", systemImage: "exclamationmark.triangle")
                }
                .help("Показывать только запуски с ошибками")
                .disabled(store.log.isEmpty)

                Button("Очистить журнал", systemImage: "trash.slash") { store.clearLog() }
                    .disabled(store.log.isEmpty)
                    .help("Удалить все записи журнала")
            }
        }
    }

    private var list: some View {
        let all = runs
        let latest = all.first(where: { !$0.isLegacy })?.id
        let days = Dictionary(grouping: all.filter { !$0.isLegacy }) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
        let legacy = all.first(where: \.isLegacy)

        return List {
            ForEach(days, id: \.key) { day, runs in
                Section(Self.dayTitle(day)) {
                    ForEach(runs) { run in
                        runGroup(run, defaultOpen: run.id == latest || !run.errors.isEmpty)
                    }
                }
            }
            if let legacy {
                Section("Ранее") {
                    runGroup(legacy, defaultOpen: false)
                }
            }
        }
    }

    private func runGroup(_ run: LogRun, defaultOpen: Bool) -> some View {
        let key = run.id?.uuidString ?? "legacy"
        return DisclosureGroup(isExpanded: Binding(
            get: { toggled[key] ?? defaultOpen },
            set: { toggled[key] = $0 }
        )) {
            ForEach(run.entries.filter { $0.run == nil }) { EntryRow(entry: $0) }
        } label: {
            RunHeader(run: run)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Сегодня" }
        if calendar.isDateInYesterday(day) { return "Вчера" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle(locale: Locale(identifier: "ru_RU")).day().month(.wide)
        return sameYear ? day.formatted(style) : day.formatted(style.year())
    }
}

/// Шапка запуска: итог, состав и время.
private struct RunHeader: View {
    let run: LogRun

    var body: some View {
        let errors = run.errors.count
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(errors > 0 ? .orange : (run.isLegacy ? .secondary : .green))
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            if !run.isLegacy {
                Text(run.date, format: .dateTime.hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        if run.isLegacy { return "clock.arrow.circlepath" }
        return run.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var title: String {
        if run.isLegacy { return "Записи старой версии" }
        guard let info = run.info else { return "Очистка прервана" }
        if let freed = info.freed, freed > 0 { return "Освобождено \(Format.bytes(freed))" }
        return info.useTrash ? "Перемещено в Корзину" : "Очистка"
    }

    private var subtitle: String {
        if run.isLegacy {
            return Format.count(run.entries.count, "запись", "записи", "записей")
        }
        var parts: [String] = []
        if let info = run.info {
            let unit = info.scope == "Проекты"
                ? Format.count(info.items, "папка", "папки", "папок")
                : Format.count(info.items, "пункт", "пункта", "пунктов")
            parts.append("\(info.scope) · \(unit)")
            parts.append(info.useTrash ? "в Корзину" : "безвозвратно")
        }
        if !run.errors.isEmpty {
            parts.append(Format.count(run.errors.count, "ошибка", "ошибки", "ошибок"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Шаг запуска; ошибки подсвечены, текст можно выделить.
private struct EntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: entry.ok ? "checkmark" : "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(entry.ok ? Color.secondary : Color.red)
                .frame(width: 14)
            Text(entry.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(entry.ok ? Color.clear : Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .font(.callout)
    }
}
