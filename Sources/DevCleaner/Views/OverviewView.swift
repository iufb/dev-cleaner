import SwiftUI

/// Сводка отвечает на вопрос «сколько можно освободить и как»:
/// главная цифра — безопасное, ниже советы с одним действием каждый.
struct OverviewView: View {
    var onOpen: (CleanupTarget.Category) -> Void
    var onOpenProjects: (_ startScan: Bool) -> Void
    @Environment(CleanerStore.self) private var store
    @State private var showCaution = false

    private var isMeasuring: Bool { !store.scanning.isEmpty }
    private var safeSize: Int64 { store.safeTargets.reduce(0) { $0 + store.size(of: $1) } }
    private var cautionSize: Int64 { store.cautionTargets.reduce(0) { $0 + store.size(of: $1) } }
    private var allSafeSelected: Bool {
        !store.safeTargets.isEmpty && store.safeTargets.allSatisfy { store.selection.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VStack(alignment: .leading, spacing: 10) {
                        UsageBar(segments: CleanupTarget.Category.allCases.map { ($0.color, store.total(for: $0)) })
                        legend
                    }
                    if let disk = store.disk {
                        DiskLine(disk: disk)
                    }
                }
                .padding(.vertical, 10)
            }

            Section("Советы") {
                safeTip
                artifactsTip
                if !store.cautionTargets.isEmpty {
                    cautionTip
                    if showCaution {
                        ForEach(store.cautionTargets.sorted { store.size(of: $0) > store.size(of: $1) }) {
                            TargetRow(target: $0)
                        }
                    }
                }
            }
        }
        .navigationTitle("Сводка")
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.bytes(safeSize))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: safeSize)
                HStack(spacing: 6) {
                    Text("можно освободить без риска · всего кэшей \(Format.bytes(store.grandTotal))")
                        .monospacedDigit()
                    if isMeasuring {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Выбрать безопасное") { store.selectSafe() }
                .buttonStyle(.secondary)
                .disabled(isMeasuring || store.isCleaning || store.safeTargets.isEmpty || allSafeSelected)
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(CleanupTarget.Category.allCases) { category in
                Button { onOpen(category) } label: {
                    HStack(spacing: 7) {
                        Circle().fill(category.color).frame(width: 8, height: 8)
                        Text(category.title)
                            .lineLimit(1)
                        Text(Format.bytes(store.total(for: category)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .opacity(store.total(for: category) > 0 ? 1 : 0.55)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Открыть «\(category.title)»")
            }
        }
        .font(.callout)
    }

    // MARK: - Советы

    private var safeTip: some View {
        let targets = store.safeTargets.sorted { store.size(of: $0) > store.size(of: $1) }
        return TipRow(
            icon: "checkmark.shield",
            tint: .green,
            title: "Безопасные кэши",
            detail: targets.isEmpty
                ? (isMeasuring ? "Считаю размеры…" : "Безопасных кэшей с данными не нашлось.")
                : "\(names(targets)). Восстановятся сами при следующей сборке или установке.",
            size: targets.isEmpty ? nil : Format.bytes(safeSize)
        ) {
            if allSafeSelected {
                Label("Выбрано", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else if !targets.isEmpty {
                Button("Выбрать") { store.selectSafe() }
                    .buttonStyle(.secondary)
                    .disabled(isMeasuring || store.isCleaning)
            }
        }
    }

    private var artifactsTip: some View {
        let found = store.filteredArtifacts
        let foundSize = found.reduce(0) { $0 + $1.size }
        let age = store.minAgeDays > 0 ? ", которые не трогали \(store.minAgeDays)+ дней" : ""
        let root = Paths.display(store.projectRoot)
        let started = store.didScanProjects || store.isScanningProjects
        let detail: String
        if store.isScanningProjects {
            detail = "Ищу в \(root)… найдено \(store.artifacts.count)."
        } else if store.didScanProjects {
            detail = found.isEmpty
                ? "В проектах\(age) ничего не нашлось."
                : "\(Format.count(found.count, "папка", "папки", "папок")) в проектах\(age): node_modules, Pods, build и другое."
        } else {
            detail = "node_modules, Pods, build и другое в \(root). Обычно это больше, чем все кэши."
        }
        return TipRow(
            icon: "folder.badge.gearshape",
            tint: .blue,
            title: "Артефакты в проектах",
            detail: detail,
            size: started ? Format.bytes(store.isScanningProjects ? store.foundSize : foundSize) : nil
        ) {
            if started {
                Button("Открыть") { onOpenProjects(false) }
                    .buttonStyle(.secondary)
            } else {
                Button("Найти") { onOpenProjects(true) }
                    .buttonStyle(.secondary)
            }
        }
    }

    private var cautionTip: some View {
        let targets = store.cautionTargets.sorted { store.size(of: $0) > store.size(of: $1) }
        return TipRow(
            icon: "exclamationmark.triangle",
            tint: .orange,
            title: "Требуют внимания",
            detail: "\(names(targets)). Восстанавливать долго или нельзя.",
            size: Format.bytes(cautionSize)
        ) {
            Button(showCaution ? "Скрыть" : "Показать") {
                withAnimation(.snappy(duration: 0.2)) { showCaution.toggle() }
            }
            .buttonStyle(.secondary)
        }
    }

    /// «pnpm store, Xcode DerivedData, Swift PM и ещё 4».
    private func names(_ targets: [CleanupTarget]) -> String {
        let head = targets.prefix(3).map(\.name).joined(separator: ", ")
        let rest = targets.count - 3
        return rest > 0 ? "\(head) и ещё \(rest)" : head
    }
}

/// Строка совета: что это, сколько занимает и одно действие справа.
private struct TipRow<Action: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let size: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text(size ?? "—")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(size == nil ? .tertiary : .primary)
                .frame(minWidth: 72, alignment: .trailing)
            action()
                .frame(minWidth: 92, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

/// Составная полоса: доля каждой категории в общем объёме кэшей.
struct UsageBar: View {
    let segments: [(color: Color, size: Int64)]

    var body: some View {
        let total = segments.reduce(0) { $0 + $1.size }
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if total > 0 {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.size > 0 {
                            segment.color
                                .frame(width: max(3, (proxy.size.width - 8) * CGFloat(segment.size) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 10)
        .animation(.smooth(duration: 0.25), value: segments.map(\.size))
        .accessibilityHidden(true)
    }
}

/// Свободное место на диске: раньше жило внизу сайдбара, теперь строкой на сводке.
private struct DiskLine: View {
    let disk: DiskInfo

    private var freeTint: Color {
        disk.freeFraction < 0.1 ? .red : (disk.freeFraction < 0.2 ? .orange : .secondary)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            (Text("Свободно ")
                + Text(Format.bytes(disk.available)).foregroundStyle(freeTint).fontWeight(.medium)
                + Text(" из \(Format.bytes(disk.total)) на диске"))
                .monospacedDigit()
            Spacer(minLength: 12)
            ProgressView(value: Double(disk.used), total: Double(max(disk.total, 1)))
                .tint(freeTint == .secondary ? .gray : freeTint)
                .frame(width: 140)
                .accessibilityLabel("Занято на диске")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
