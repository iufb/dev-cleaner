import SwiftUI

struct OverviewView: View {
    var onOpen: (CleanupTarget.Category) -> Void
    @Environment(CleanerStore.self) private var store

    private var topTargets: [CleanupTarget] {
        store.targets
            .filter { store.size(of: $0) > 0 }
            .sorted { store.size(of: $0) > store.size(of: $1) }
            .prefix(10)
            .map { $0 }
    }

    private var isMeasuring: Bool { !store.scanning.isEmpty }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    UsageBar(segments: CleanupTarget.Category.allCases.map { ($0.color, store.total(for: $0)) })
                    if let disk = store.disk {
                        DiskLine(disk: disk)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 10)
            }

            Section("По категориям") {
                ForEach(CleanupTarget.Category.allCases) { category in
                    CategoryRow(category: category,
                                size: store.total(for: category),
                                total: store.grandTotal) { onOpen(category) }
                }
            }

            Section("Самое тяжёлое") {
                if topTargets.isEmpty {
                    Text(isMeasuring ? "Считаю…" : "Ничего не найдено")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topTargets) { TargetRow(target: $0) }
                }
            }

            Section {
                Label("Ещё больше места обычно занимают node_modules, Pods и build внутри проектов. Их ищет раздел «Артефакты сборки».",
                      systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Сводка")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.bytes(store.grandTotal))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: store.grandTotal)
                HStack(spacing: 6) {
                    Text(subtitle)
                    if isMeasuring {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Выбрать все безопасные") { store.selectSafe() }
                .disabled(isMeasuring || store.isCleaning)
        }
    }

    private var subtitle: String {
        guard let disk = store.disk, disk.total > 0, store.grandTotal > 0 else {
            return "занято кэшами разработки"
        }
        let share = Double(store.grandTotal) / Double(disk.total)
        return "занято кэшами разработки · \(share.formatted(.percent.precision(.fractionLength(share < 0.1 ? 1 : 0)))) диска"
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

private struct CategoryRow: View {
    let category: CleanupTarget.Category
    let size: Int64
    let total: Int64
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(category.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                    Text(category.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if size > 0, total > 0 {
                    let share = Double(size) / Double(total)
                    Text(share < 0.01 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
                Text(Format.bytes(size))
                    .monospacedDigit()
                    .foregroundStyle(size > 0 ? .primary : .tertiary)
                    .frame(minWidth: 72, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title), \(Format.bytes(size))")
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
