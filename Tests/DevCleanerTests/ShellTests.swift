import Foundation
import Testing
@testable import DevCleaner

@Suite struct ShellTests {
    private func makeExecutable(_ url: URL, _ script: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @Test func resolvesPathFromLoginShellIgnoringRcNoise() throws {
        let tmp = try TempDir()
        let shell = tmp.url.appendingPathComponent("fakeshell")
        // Подменный shell: печатает мусор из «rc-файлов», а потом выполняет команду через sh
        // с PATH, который пользователь настроил бы в config.fish или .zshrc.
        try makeExecutable(shell, """
        #!/bin/sh
        echo "Welcome to fish"
        for last; do :; done
        PATH=/opt/user/bin:/usr/bin:/bin /bin/sh -c "$last"
        """)
        #expect(Shell.resolvePath(shell: shell.path) == "/opt/user/bin:/usr/bin:/bin")
    }

    @Test func brokenShellGivesNil() throws {
        let tmp = try TempDir()
        let shell = tmp.url.appendingPathComponent("broken")
        try makeExecutable(shell, "#!/bin/sh\nexit 1\n")
        #expect(Shell.resolvePath(shell: shell.path) == nil)
    }

    @Test func hangingShellTimesOut() throws {
        let tmp = try TempDir()
        let shell = tmp.url.appendingPathComponent("hang")
        try makeExecutable(shell, "#!/bin/sh\nexec sleep 30\n")
        let start = Date()
        #expect(Shell.resolvePath(shell: shell.path, timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func runSyncReportsTimeout() throws {
        #expect(throws: Shell.TimedOut.self) {
            try Shell.runSync(executable: "/bin/sleep", arguments: ["30"], environment: nil, timeout: 0.3)
        }
    }

    @Test func whichFindsOnlyExecutablesInPath() throws {
        let tmp = try TempDir()
        try makeExecutable(tmp.url.appendingPathComponent("b/pnpm"), "#!/bin/sh\n")
        try tmp.file("a/pnpm") // не исполняемый
        let path = "\(tmp.url.path)/a:\(tmp.url.path)/b"
        #expect(Shell.which("pnpm", path: path)?.path == "\(tmp.url.path)/b/pnpm")
        #expect(Shell.which("docker", path: path) == nil)
    }

    @Test func commandTargetRequiresFirstWord() {
        let t = CleanupTarget(id: "x", name: "x", detail: "", category: .web, paths: [],
                              action: .command("pnpm store prune"))
        #expect(t.requiredTool == "pnpm")
        let d = CleanupTarget(id: "y", name: "y", detail: "", category: .web, paths: ["~/x"])
        #expect(d.requiredTool == nil)
    }

    @Test func commandsRunFromHomeDirectory() async throws {
        let pwd = try await Shell.run("pwd -P")
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        #expect(pwd == home)
    }

    @Test func errorSummaryKeepsTheCauseNotTheStackTrace() {
        let output = """
        node:internal/bootstrap/switches/does_own_process_state:142
            cachedCwd = rawMethods.cwd();
        Error: ENOENT: no such file or directory, uv_cwd
            at process.wrappedCwd (node:internal/bootstrap/switches/does_own_process_state:142:28)
            at Module._compile (node:internal/modules/cjs/loader:1929:14)
            at Module.load (node:internal/modules/cjs/loader:1651:32)
        """
        let summary = Shell.errorSummary(output)
        #expect(summary.contains("ENOENT"))
        #expect(!summary.contains("Module.load"))
        #expect(summary.hasSuffix("…"))
        #expect(Shell.errorSummary("ERR_PNPM_NO_STORE") == "ERR_PNPM_NO_STORE")
    }
}
