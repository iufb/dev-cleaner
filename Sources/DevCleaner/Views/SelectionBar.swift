import SwiftUI

/// Плашка внизу окна: появляется, только когда что-то выбрано, и ведёт к подтверждению очистки.
/// Одна и та же для глобальных кэшей и для артефактов проектов.
struct SelectionBar: View {
    let summary: String
    let actionTitle: String
    var busy = false
    var disabled = false
    let onClear: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if busy {
                ProgressView().controlSize(.small)
            }
            Text(summary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, busy ? 0 : 4)

            Button("Снять выбор", action: onClear)
                .buttonStyle(.quiet)
                .disabled(busy)

            Button(action: onAction) {
                Text(actionTitle)
                    .monospacedDigit()
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.primary(.large))
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(busy || disabled)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .padding(.bottom, 16)
        .padding(.horizontal, 16)
    }
}
