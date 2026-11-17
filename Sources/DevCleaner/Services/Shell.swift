import Foundation

enum Shell {
    struct Failure: LocalizedError {
        let output: String
        var errorDescription: String? { output }
    }

    /// Запускает команду через `zsh -lc`: приложение из Finder не видит PATH,
    /// а login-shell подтягивает его из ~/.zprofile (brew, nvm, pnpm и т.д.).
    static func run(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Читаем вывод в фоне до EOF, чтобы процесс не завис на переполненном pipe.
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let message = output.isEmpty ? "код выхода \(process.terminationStatus)" : output
                    continuation.resume(throwing: Failure(output: String(message.suffix(500))))
                }
            }
        }
    }
}
