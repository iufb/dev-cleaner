import Foundation

/// Считает реально занятое на диске место (allocated size), как Finder.
enum SizeCalculator {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
    ]

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return fileSize(url) }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true } // нет доступа к подпапке — просто пропускаем
        ) else { return 0 }

        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            total += fileSize(item)
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true
        else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
