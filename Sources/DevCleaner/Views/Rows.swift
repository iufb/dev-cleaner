import SwiftUI

/// Общий вид строк в списках целей и артефактов: скруглённая подложка вместо системных
/// разделителей, мягкая подсветка при наведении, лёгкий акцент у выбранной строки.
struct RowChrome: ViewModifier {
    var selected = false
    var hoverable = true
    var indent: CGFloat = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CardMetrics.rowPadding)
            .padding(.vertical, 7)
            .frame(minHeight: 36)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.leading, indent)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && hoverable }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .environment(\.rowHovering, hovering)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(hovering ? 0.16 : 0.11) }
        return Color.primary.opacity(hovering ? 0.05 : 0)
    }
}

extension View {
    func rowChrome(selected: Bool = false, hoverable: Bool = true, indent: CGFloat = 0) -> some View {
        modifier(RowChrome(selected: selected, hoverable: hoverable, indent: indent))
    }
}

private struct RowHoveringKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Наведён ли курсор на строку: по нему показывается «⋯».
    var rowHovering: Bool {
        get { self[RowHoveringKey.self] }
        set { self[RowHoveringKey.self] = newValue }
    }
}

/// Небольшой чип: тип артефакта, «команда» и подобные метки.
struct Tag: View {
    let text: String
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .fixedSize()
    }
}

/// Размер в строке: моноширинные цифры, от 1 ГБ — полужирный. Одно правило на все списки.
struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(Format.bytes(bytes))
            .monospacedDigit()
            .fontWeight(bytes >= 1_000_000_000 ? .semibold : .regular)
    }
}

/// «⋯» с меню действий строки: виден при наведении на строку и при фокусе.
struct RowMenu<Actions: View>: View {
    let label: String
    @ViewBuilder let actions: () -> Actions
    @Environment(\.rowHovering) private var hovering

    var body: some View {
        Menu { actions() } label: { MoreMenuLabel() }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: CardMetrics.menuColumn)
            .opacity(hovering ? 1 : 0)
            .help("Действия")
            .accessibilityLabel(label)
    }
}

/// Метрики карточек со строками: из них считаются выравнивания заголовков и разделителей.
enum CardMetrics {
    static let padding: CGFloat = 4          // отступ строк от края карточки
    static let rowPadding: CGFloat = 10      // внутренний отступ строки (RowChrome)
    static let leadingColumn: CGFloat = 16   // колонка галочки
    static let spacing: CGFloat = 10         // расстояние между колонками строки
    static let menuColumn: CGFloat = 26      // колонка «⋯»
    static let maxWidth: CGFloat = 880

    /// Где начинается текст строки: под ним начинаются разделители.
    static var textInset: CGFloat { padding + rowPadding + leadingColumn + spacing }
    /// Правый край колонки размеров: по нему выравниваются суммы в заголовках.
    static var sizeTrailing: CGFloat { padding + rowPadding + menuColumn + spacing }
}

/// Подложка карточки: светлая панель со скруглением и тонкой рамкой.
struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(CardMetrics.padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Карточка без списка: баннер, пустое состояние.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface())
    }
}

/// Карточка группы: заголовок над ней, строки внутри, тонкие линии между строками.
/// `top` — необязательная первая строка (например, «Пустые и не установленные»).
struct RowCard<Item: Identifiable, Row: View>: View {
    var title: String? = nil
    var leading: AnyView? = nil
    var trailing: AnyView? = nil
    var top: AnyView? = nil
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: CardMetrics.spacing) {
                    (leading ?? AnyView(EmptyView()))
                        .frame(width: CardMetrics.leadingColumn, alignment: .center)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    trailing
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.leading, CardMetrics.padding + CardMetrics.rowPadding)
                .padding(.trailing, CardMetrics.sizeTrailing)
            }
            VStack(spacing: 0) {
                if let top { top }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 || top != nil {
                        Divider().padding(.leading, CardMetrics.textInset - CardMetrics.padding)
                    }
                    row(item)
                }
            }
            .modifier(CardSurface())
        }
    }
}

/// Прокручиваемая страница карточек на фоне окна, ограниченная по ширине.
struct CardPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .frame(maxWidth: CardMetrics.maxWidth)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 90) // место под плашку выбора
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Строка-переключатель «Пустые и не установленные · N» и подобные свёрнутые группы.
struct FoldRow: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowChrome()
    }
}

/// Шеврон раскрытия справа в строке группы.
struct DisclosureChevron: View {
    let expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: CardMetrics.menuColumn)
            .animation(.snappy(duration: 0.2), value: expanded)
    }
}
