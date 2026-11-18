import SwiftUI

/// Единая система кнопок (#20): капсулы одной формы, четыре вида и кнопка-иконка.
///
/// - `primary` — заливка акцентом, не больше одной на экран.
/// - `secondary` — мягкая серая заливка без рамки.
/// - `quiet` — текст акцентом без фона, вместо ссылок.
/// - `destructive` — красная заливка, только для финального безвозвратного удаления.
/// - `icon` — круглая кнопка-иконка без фона.
struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }
    enum Size {
        case regular, large
        var height: CGFloat { self == .large ? 32 : 28 }
    }

    var kind: Kind
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, kind: kind, size: size)
    }

    private struct Styled: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: kind == .secondary || kind == .quiet ? .medium : .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .quiet ? 10 : (size == .large ? 18 : 13))
                .frame(height: size.height)
                .background(background, in: Capsule())
                .overlay {
                    if isFocused {
                        Capsule().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                    }
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 && isEnabled }
        }

        private var foreground: Color {
            switch kind {
            case .primary, .destructive: .white
            case .secondary: .primary
            case .quiet: .accentColor
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                return Color.accentColor.opacity(pressed ? 0.8 : (hovering ? 0.9 : 1))
            case .destructive:
                return Color.red.opacity(pressed ? 0.8 : (hovering ? 0.9 : 1))
            case .secondary:
                return Color.primary.opacity(pressed ? 0.16 : (hovering ? 0.11 : 0.07))
            case .quiet:
                return Color.accentColor.opacity(pressed ? 0.16 : (hovering ? 0.1 : 0))
            }
        }
    }
}

/// Круглая кнопка-иконка: «⋯» и подобное.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.08 : 0)), in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var primary: AppButtonStyle { .init(kind: .primary) }
    static var secondary: AppButtonStyle { .init(kind: .secondary) }
    static var quiet: AppButtonStyle { .init(kind: .quiet) }
    static var destructive: AppButtonStyle { .init(kind: .destructive) }
    static func primary(_ size: AppButtonStyle.Size) -> AppButtonStyle { .init(kind: .primary, size: size) }
    static func secondary(_ size: AppButtonStyle.Size) -> AppButtonStyle { .init(kind: .secondary, size: size) }
    static func destructive(_ size: AppButtonStyle.Size) -> AppButtonStyle { .init(kind: .destructive, size: size) }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { .init() }
}

/// «⋯» для меню действий строки.
struct MoreMenuLabel: View {
    @State private var hovering = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Color.primary.opacity(hovering ? 0.08 : 0), in: Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
    }
}
