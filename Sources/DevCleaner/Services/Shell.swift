import Foundation

enum Shell {
    struct Failure: LocalizedError {
        let output: String
        var errorDescription: String? { output }
    }

    /// Запасной PATH, если login shell пользователя не ответил.
    static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Login shell пользователя: из базы пользователей, затем `$SHELL`, затем zsh.
    static var userShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        if let env = ProcessInfo.processInfo.environment["SHELL"], !env.isEmpty { return env }
        return "/bin/zsh"
    }

    /// PATH из login shell пользователя. Считается один раз за запуск.
    /// Приложение из Finder не видит PATH, настроенный в `.zshrc`, `config.fish`, nvm и т. п.
    static let userPath: String = resolvePath(shell: userShell) ?? fallbackPath

    private static let beginMarker = "__DEVCLEANER_PATH_BEGIN__"
    private static let endMarker = "__DEVCLEANER_PATH_END__"

    /// Запускает `shell` как интерактивный login shell и читает из него PATH.
    /// Команда понятна sh, bash, zsh и fish. Маркеры отсекают то, что печатают rc-файлы.
    static func resolvePath(shell: String, timeout: TimeInterval = 10) -> String? {
        let script = "echo \(beginMarker); printenv PATH; echo \(endMarker)"
        for args in [["-l", "-i", "-c", script], ["-l", "-c", script]] {
            guard let result = try? runSync(
                executable: shell, arguments: args, environment: nil, timeout: timeout
            ) else { continue }
            if let path = parsePath(result.output) { return path }
        }
        return nil
    }

    static func parsePath(_ output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        guard let begin = lines.lastIndex(of: beginMarker),
              let end = lines[begin...].firstIndex(of: endMarker),
              end == begin + 2
        else { return nil }
        let path = lines[begin + 1].trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : path
    }

    /// Ищет исполняемый файл в PATH, как `command -v`.
    static func which(_ tool: String, path: String = userPath) -> URL? {
        if tool.contains("/") {
            return FileManager.default.isExecutableFile(atPath: tool) ? URL(fileURLWithPath: tool) : nil
        }
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Запускает команду через `/bin/sh -c` с PATH из login shell пользователя.
    static func run(_ command: String, timeout: TimeInterval = 600) async throws -> String {
        let env = ProcessInfo.processInfo.environment.merging(["PATH": userPath]) { $1 }
        return try await Task.detached(priority: .userInitiated) {
            let result = try runSync(executable: "/bin/sh", arguments: ["-c", command],
                                     environment: env, timeout: timeout)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0 else {
                throw Failure(output: output.isEmpty ? "код выхода \(result.status)" : errorSummary(output))
            }
            return output
        }.value
    }

    /// Суть ошибки из вывода команды: первые строки, где обычно и стоит причина.
    /// Хвост — это чаще всего стектрейс, по нему ничего не понять.
    static func errorSummary(_ output: String, maxLines: Int = 4, maxLength: Int = 400) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var text = lines.prefix(maxLines).joined(separator: "\n")
        if text.count > maxLength { text = String(text.prefix(maxLength)) }
        return lines.count > maxLines || text.count < lines.joined(separator: "\n").count ? text + " …" : text
    }

    struct TimedOut: LocalizedError {
        let seconds: TimeInterval
        let command: String
        var errorDescription: String? {
            "команда не завершилась за \(Int(seconds)) с и была остановлена: \(command)"
        }
    }

    /// Синхронно запускает процесс с таймаутом. Вывод stdout и stderr объединён.
    static func runSync(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        // Текущая папка приложения может исчезнуть: при запуске из Xcode она лежит в DerivedData,
        // которую мы же и чистим. Команды запускаем из домашней папки.
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = OutputBuffer()
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in buffer.append(handle.availableData) }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            reader.readabilityHandler = nil
            throw TimedOut(seconds: timeout, command: ([executable] + arguments).joined(separator: " "))
        }

        // Дочитываем остаток без блокировки: внук процесса может держать pipe открытым.
        reader.readabilityHandler = nil
        let fd = reader.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(Data(chunk[0..<n]))
        }

        return (process.terminationStatus, buffer.string)
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
        }

        var string: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
