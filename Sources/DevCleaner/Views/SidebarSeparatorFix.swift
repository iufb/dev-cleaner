import SwiftUI
import AppKit

/// Убирает разделитель заголовка окна над колонкой сайдбара.
///
/// При первой раскладке `NavigationSplitView` macOS рисует над сайдбаром линию
/// titlebar separator, которая пропадает только после ресайза окна. Сайдбару она
/// не нужна: у него своя подложка. Разделитель над содержимым не трогаем.
struct SidebarSeparatorFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Контроллеры сплита появляются чуть позже самого окна.
            DispatchQueue.main.async { Self.apply(in: window) }
        }

        static func apply(in window: NSWindow) {
            // SwiftUI держит NSSplitView внутри своей обёртки, контроллер — его делегат.
            guard let frame = window.contentView?.superview else { return }
            for splitView in splitViews(in: frame) {
                (splitView.delegate as? NSSplitViewController)?
                    .splitViewItems.first?.titlebarSeparatorStyle = .none
            }
        }

        private static func splitViews(in view: NSView) -> [NSSplitView] {
            var result: [NSSplitView] = []
            if let split = view as? NSSplitView { result.append(split) }
            for subview in view.subviews { result += splitViews(in: subview) }
            return result
        }
    }
}
