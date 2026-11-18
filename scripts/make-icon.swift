// Собирает иконку из рисунка в Sources/DevCleaner/Views/AppIconArt.swift.
// Запускается не напрямую, а через scripts/make-icon.sh, который подклеивает рисунок:
//
//   ./scripts/make-icon.sh build/AppIcon.icns                                  # .icns для build-app.sh
//   ./scripts/make-icon.sh Resources/Assets.xcassets/AppIcon.appiconset        # каталог для Xcode
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

/// Имя файла → размер в пикселях. До 32 точек включительно — упрощённая версия.
let files: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2), ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2), ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

@MainActor
func writePNGs(to dir: URL) throws {
    for file in files {
        try png(size: file.points * file.scale, simple: file.points <= 32)
            .write(to: dir.appendingPathComponent("\(file.name).png"))
    }
}

/// Каталог ассетов для Xcode-проекта: PNG всех размеров и Contents.json.
@MainActor
func makeAppIconSet(at dir: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try writePNGs(to: dir)
    let images = files.map { file in
        """
            { "filename" : "\(file.name).png", "idiom" : "mac", "scale" : "\(file.scale)x", "size" : "\(file.points)x\(file.points)" }
        """
    }
    let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : { "author" : "scripts/make-icon.swift", "version" : 1 }
    }

    """
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

/// .icns для бандла, собранного scripts/build-app.sh, и превью рядом.
@MainActor
func makeICNS(at output: String) throws {
    let fm = FileManager.default
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: iconset) }
    try writePNGs(to: iconset)

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
}

@MainActor
func main() throws {
    let output = CommandLine.arguments.dropFirst().first ?? "build/AppIcon.icns"
    if output.hasSuffix(".appiconset") {
        try makeAppIconSet(at: URL(fileURLWithPath: output))
    } else {
        try makeICNS(at: output)
    }
    print("Готово: \(output)")
}

try MainActor.assumeIsolated { try main() }
