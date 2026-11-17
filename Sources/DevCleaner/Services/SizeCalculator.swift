import Foundation

/// Считает реально занятое на диске место (allocated size), как Finder.
/// Файл с несколькими жёсткими ссылками учитывается один раз.
enum SizeCalculator {
    /// Уже посчитанные inode файлов с несколькими жёсткими ссылками.
    struct Seen {
        fileprivate var inodes: Set<Inode> = []
    }

    fileprivate struct Inode: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .linkCountKey,
    ]

    static func size(of url: URL) -> Int64 {
        var seen = Seen()
        return size(of: url, seen: &seen)
    }

    static func size(of urls: [URL]) -> Int64 {
        var seen = Seen()
        return urls.reduce(0) { $0 + size(of: $1, seen: &seen) }
    }

    static func size(of url: URL, seen: inout Seen) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return fileSize(url, seen: &seen) }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true } // нет доступа к подпапке — просто пропускаем
        ) else { return 0 }

        var total: Int64 = 0
        while let item = enumerator.nextObject() as? URL {
            total += fileSize(item, seen: &seen)
        }
        return total
    }

    private static func fileSize(_ url: URL, seen: inout Seen) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true
        else { return 0 }

        if (values.linkCount ?? 1) > 1 {
            var info = stat()
            if lstat(url.path, &info) == 0 {
                let inserted = seen.inodes.insert(Inode(device: info.st_dev, inode: info.st_ino)).inserted
                if !inserted { return 0 }
            }
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
