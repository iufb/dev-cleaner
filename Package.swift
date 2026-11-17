// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevCleaner",
            path: "Sources/DevCleaner"
        ),
        .testTarget(
            name: "DevCleanerTests",
            dependencies: ["DevCleaner"],
            path: "Tests/DevCleanerTests"
        ),
    ]
)
