import SwiftUI
import Charts

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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(store.grandTotal))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("занято кэшами разработки")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Выбрать все безопасные") { store.selectSafe() }
                    }

                    Chart(CleanupTarget.Category.allCases) { category in
                        BarMark(
                            x: .value("ГБ", Double(store.total(for: category)) / 1_073_741_824),
                            y: .value("Категория", category.title)
                        )
                        .foregroundStyle(by: .value("Категория", category.title))
                        .annotation(position: .trailing) {
                            Text(Format.bytes(store.total(for: category)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartXAxisLabel("ГБ")
                    .frame(height: 170)

                    HStack {
                        ForEach(CleanupTarget.Category.allCases) { category in
                            Button(category.title) { onOpen(category) }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 8)
            }

            Section("Самое тяжёлое") {
                if topTargets.isEmpty {
                    Text(store.scanning.isEmpty ? "Ничего не найдено" : "Считаю…")
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
}
