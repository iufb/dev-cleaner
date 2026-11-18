// Собирает AppIcon.icns из рисунка в Sources/DevCleaner/Views/AppIconArt.swift.
// Запускается не напрямую, а через scripts/make-icon.sh, который подклеивает рисунок:
//
//   ./scripts/make-icon.sh build/AppIcon.icns
//
// Для 16 и 32 точек рисуется упрощённая версия: толще скобки, один штрих.
import AppKit
import SwiftUI

@MainActor
func png(size: Int, simple: Bool) -> Data {
    let renderer = ImageRenderer(content: AppIconArt(simple: simple))
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
