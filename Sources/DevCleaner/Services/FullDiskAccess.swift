import AppKit

/// Проверка «Полного доступа к диску». Прямого API нет, поэтому пробуем открыть
/// файл, который TCC отдаёт только приложениям с этим разрешением.
enum FullDiskAccess {
    static func isGranted(home: String = NSHomeDirectory()) -> Bool {
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            return false
        }
        // Проверочных файлов нет — судим по Корзине.
        return (try? FileManager.default.contentsOfDirectory(atPath: home + "/.Trash")) != nil
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
