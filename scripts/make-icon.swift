// Рисует иконку DevCleaner и собирает AppIcon.icns.
//
//   swift scripts/make-icon.swift build/AppIcon.icns
//
// Иконка: фигурные скобки кода и взмах метлы на синей плитке.
// Для 16 и 32 точек рисуется упрощённая версия: толще скобки, один штрих.
import AppKit
import SwiftUI

/// Сетка иконок macOS: холст 1024, плитка 824 с отступом 100.
struct AppIcon: View {
    /// Упрощённая версия для маленьких размеров.
    var simple = false

    var body: some View {
        Canvas { context, size in
            let s = size.width / 1024
            context.scaleBy(x: s, y: s)

            let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
            let tile = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: tileRect)

            // Тень плитки.
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 14))
            shadowed.fill(tile, with: .color(.black))

            // Плитка: синий градиент сверху вниз и мягкий блик слева сверху.
            context.fill(tile, with: .linearGradient(
                Gradient(colors: [Color(red: 0.31, green: 0.60, blue: 1.0), Color(red: 0.08, green: 0.27, blue: 0.80)]),
                startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
            context.fill(tile, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                center: CGPoint(x: 300, y: 180), startRadius: 0, endRadius: 620))
            // Тонкий светлый кант сверху и тёмный снизу — объём края.
            context.stroke(tile, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.35), .white.opacity(0), .black.opacity(0.25)]),
                startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)), lineWidth: 4)

            var art = context
            art.addFilter(.shadow(color: Color(red: 0, green: 0.1, blue: 0.4).opacity(0.35), radius: 10, x: 0, y: 8))

            // Скобки.
            let braceWidth: CGFloat = simple ? 84 : 58
            let style = StrokeStyle(lineWidth: braceWidth, lineCap: .round, lineJoin: .round)
            art.stroke(brace(left: true), with: .color(.white), style: style)
            art.stroke(brace(left: false), with: .color(.white), style: style)

            // Взмах метлы между скобками: дуги сужаются и бледнеют к краю.
            let sweeps: [(CGFloat, CGFloat, Double)] = simple
                ? [(0, 62, 1)]
                : [(0, 34, 1), (44, 24, 0.72), (84, 16, 0.45)]
            for (offset, width, opacity) in sweeps {
                var arc = Path()
                arc.move(to: CGPoint(x: 432 + offset * 0.4, y: 598 + offset))
                arc.addQuadCurve(to: CGPoint(x: 604 + offset * 0.2, y: 420 + offset),
                                 control: CGPoint(x: 500 + offset * 0.3, y: 440 + offset))
                art.stroke(arc, with: .color(.white.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .frame(width: 1024, height: 1024)
    }

    /// Фигурная скобка: левая или зеркальная правая.
    private func brace(left: Bool) -> Path {
        var p = Path()
        let x: (CGFloat) -> CGFloat = { left ? $0 : 1024 - $0 }
        p.move(to: CGPoint(x: x(410), y: 296))
        p.addCurve(to: CGPoint(x: x(346), y: 390), control1: CGPoint(x: x(350), y: 296), control2: CGPoint(x: x(346), y: 330))
        p.addLine(to: CGPoint(x: x(346), y: 456))
        p.addCurve(to: CGPoint(x: x(292), y: 512), control1: CGPoint(x: x(346), y: 492), control2: CGPoint(x: x(326), y: 512))
        p.addCurve(to: CGPoint(x: x(346), y: 568), control1: CGPoint(x: x(326), y: 512), control2: CGPoint(x: x(346), y: 532))
        p.addLine(to: CGPoint(x: x(346), y: 634))
        p.addCurve(to: CGPoint(x: x(410), y: 728), control1: CGPoint(x: x(346), y: 694), control2: CGPoint(x: x(350), y: 728))
        return p
    }
}

@MainActor
func png(size: Int, simple: Bool) -> Data {
    let renderer = ImageRenderer(content: AppIcon(simple: simple))
    renderer.scale = CGFloat(size) / 1024
    guard let cg = renderer.cgImage else { fatalError("Не удалось нарисовать иконку \(size)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
func main() throws {
    let output = CommandLine.arguments.dropFirst().first ?? "build/AppIcon.icns"
    let fm = FileManager.default
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: iconset) }

    // Имя файла → размер в пикселях. До 32 точек включительно — упрощённая версия.
    let files: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, pixels) in files {
        let points = name.hasSuffix("@2x") ? pixels / 2 : pixels
        try png(size: pixels, simple: points <= 32).write(to: iconset.appendingPathComponent("\(name).png"))
    }

    // Превью рядом с .icns: крупная и упрощённая версии.
    let dir = URL(fileURLWithPath: output).deletingLastPathComponent()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try png(size: 1024, simple: false).write(to: dir.appendingPathComponent("AppIcon.png"))
    try png(size: 256, simple: true).write(to: dir.appendingPathComponent("AppIcon-small.png"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("iconutil завершился с кодом \(process.terminationStatus)") }
    print("Готово: \(output)")
}

try MainActor.assumeIsolated { try main() }
