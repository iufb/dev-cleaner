import Foundation
import Testing
@testable import DevCleaner

@Suite struct RulesTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let artifact: String
        let marker: String
        var testDescription: String { "\(artifact) + \(marker)" }
    }

    static let cases: [Case] = [
        .init(artifact: "__pycache__", marker: "main.py"),
        .init(artifact: ".pytest_cache", marker: "pyproject.toml"),
        .init(artifact: ".mypy_cache", marker: "mypy.ini"),
        .init(artifact: ".ruff_cache", marker: "ruff.toml"),
        .init(artifact: ".tox", marker: "tox.ini"),
        .init(artifact: ".output", marker: "nuxt.config.ts"),
        .init(artifact: ".vercel", marker: "vercel.json"),
        .init(artifact: ".docusaurus", marker: "docusaurus.config.js"),
        .init(artifact: ".yarn/cache", marker: ".yarnrc.yml"),
        .init(artifact: ".zig-cache", marker: "build.zig"),
        .init(artifact: "zig-cache", marker: "build.zig"),
        .init(artifact: "_build", marker: "mix.exs"),
        .init(artifact: "deps", marker: "mix.exs"),
        .init(artifact: "cmake-build-debug", marker: "CMakeLists.txt"),
        .init(artifact: "cmake-build-release", marker: "CMakeLists.txt"),
        .init(artifact: "bin", marker: "App.csproj"),
        .init(artifact: "obj", marker: "App.csproj"),
        .init(artifact: "bin", marker: "Solution.sln"),
    ]

    private func scan(_ tmp: TempDir) -> [String] {
        ProjectScanner.scan(root: tmp.url, home: tmp.url.appendingPathComponent("nohome"))
            .map { String($0.url.path.dropFirst(tmp.url.path.count + 1)) }
    }

    @Test(arguments: cases)
    func findsArtifactWithMarker(_ c: Case) throws {
        let tmp = try TempDir()
        try tmp.file("proj/\(c.marker)")
        try tmp.file("proj/\(c.artifact)/blob")
        #expect(scan(tmp) == ["proj/\(c.artifact)"])
    }

    @Test(arguments: cases)
    func ignoresSameNameOutsideProject(_ c: Case) throws {
        let tmp = try TempDir()
        try tmp.file("proj/README.md")
        try tmp.file("proj/\(c.artifact)/blob")
        #expect(scan(tmp).isEmpty)
    }

    @Test func everyRuleHasAMarker() {
        for rule in ProjectScanner.rules { #expect(!rule.markers.isEmpty, "\(rule.pattern)") }
    }

    @Test(arguments: [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".expo", ".angular", "DerivedData", ".venv"])
    func formerlyMarkerlessRulesNeedMarkers(_ name: String) throws {
        let tmp = try TempDir()
        try tmp.file("somewhere/\(name)/blob")
        #expect(scan(tmp).isEmpty)
    }
}
