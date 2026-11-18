import SwiftUI

/// Одно окно на весь путь очистки: подтверждение → прогресс → результат.
/// Общее для глобальных кэшей и артефактов проектов.
struct ConfirmationSheet: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let size: String
    }

    struct Section {
        let title: String
        let rows: [Row]
    }

    let title: String
    /// Рискованное: всегда перечислено явно.
    let warning: Section?
    /// Всё остальное: свёрнуто, если строк много.
    let others: Section?
    /// Режим удаления выбирается здесь, в момент решения.
    @Binding var useTrash: Bool
    let notes: (_ useTrash: Bool) -> [String]
    let confirmTitle: (_ useTrash: Bool) -> String
    let onConfirm: () async -> Void
    let onOpenLog: () -> Void

    private enum Phase { case confirm, running, done }

    @Environment(CleanerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .confirm
    @State private var showOthers: Bool

    init(title: String, warning: Section?, others: Section?, useTrash: Binding<Bool>,
         notes: @escaping (Bool) -> [String], confirmTitle: @escaping (Bool) -> String,
         onConfirm: @escaping () async -> Void, onOpenLog: @escaping () -> Void) {
        self.title = title
        self.warning = warning
        self.others = others
        self._useTrash = useTrash
        self.notes = notes
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onOpenLog = onOpenLog
        self._showOthers = State(initialValue: (others?.rows.count ?? 0) <= 5)
    }

    var body: some View {
        Group {
            switch phase {
            case .confirm: confirmView
            case .running: runningView
            case .done: doneView
            }
        }
        .padding(22)
        .frame(width: 540)
        .interactiveDismissDisabled(phase == .running)
        .animation(.snappy(duration: 0.2), value: phase)
    }

    // MARK: - Подтверждение

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            if let warning, !warning.rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(warning.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    rows(warning.rows)
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let others, !others.rows.isEmpty {
                DisclosureGroup(isExpanded: $showOthers) {
                    ScrollView {
                        rows(others.rows)
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: 180)
                } label: {
                    Text(others.title)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Text("Куда")
                    .foregroundStyle(.secondary)
                Picker("Куда", selection: $useTrash) {
                    Text("В Корзину").tag(true)
                    Text("Безвозвратно").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes(useTrash), id: \.self) { note in
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle(useTrash)) { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(useTrash ? .accentColor : .red)
                    .monospacedDigit()
            }
            .controlSize(.large)
        }
    }

    private func rows(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(row.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(row.size)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .help(row.subtitle)
            }
        }
    }

    private func start() {
        phase = .running
        Task {
            await onConfirm()
            phase = .done
        }
    }

    // MARK: - Прогресс

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(useTrash ? "Перемещаю в Корзину…" : "Очищаю…")
                .font(.title2.weight(.semibold))
            if let progress = store.cleanProgress, progress.total > 1 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                Text("\(progress.done + 1) из \(progress.total): \(progress.current)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(store.cleanProgress?.current ?? " ")
                    .foregroundStyle(.secondary)
            }
            Text("Не закрывайте окно до конца очистки.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Результат

    private var doneView: some View {
        let report = store.lastReport
        let errors = report?.errors ?? []

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(errors.isEmpty ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(report))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Text(detail(report))
                        .foregroundStyle(.secondary)
                }
            }

            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Не получилось: \(Format.count(errors.count, "ошибка", "ошибки", "ошибок"))")
                        .font(.callout.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                                Text(error)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                Spacer()
                Button("Открыть журнал") {
                    dismiss()
                    onOpenLog()
                }
                Button("Готово") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
    }

    private func headline(_ report: CleanerStore.CleanReport?) -> String {
        guard let report else { return "Готово" }
        if let freed = report.freed, freed > 0 { return "Освобождено \(Format.bytes(freed))" }
        return report.useTrash ? "Перемещено в Корзину" : "Готово"
    }

    private func detail(_ report: CleanerStore.CleanReport?) -> String {
        guard let report else { return "Подробности в журнале." }
        if let freed = report.freed, freed > 0 {
            return report.useTrash
                ? "Часть места вернётся после очистки Корзины."
                : "Безопасные кэши восстановятся сами при следующей сборке."
        }
        if report.useTrash { return "Место освободится после очистки Корзины." }
        if report.freed == nil { return "Не удалось узнать свободное место на диске." }
        return "Свободное место почти не изменилось."
    }
}
