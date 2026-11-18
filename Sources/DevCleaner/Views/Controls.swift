import SwiftUI

/// Табы (#20): капсула-дорожка в цвет вторичной кнопки, выбранный сегмент — светлая капсула, которая переезжает.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var size: AppButtonStyle.Size = .regular

    @Namespace private var namespace
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Segment(
                    title: option.title,
                    isSelected: option.value == selection,
                    height: size.height - 4,
                    namespace: namespace
                ) {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .opacity(isEnabled ? 1 : 0.4)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private struct Segment: View {
        let title: String
        let isSelected: Bool
        let height: CGFloat
        let namespace: Namespace.ID
        let action: () -> Void

        @State private var hovering = false
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected || hovering ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: height)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.12), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// Селект (#20): вторичная кнопка с подписью выбранного и шевроном; список открывается во всплывающем окне.
struct SelectButton<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(.snappy(duration: 0.2), value: open)
            }
        }
        .buttonStyle(.secondary)
        .fixedSize()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            content()
        }
    }
}
