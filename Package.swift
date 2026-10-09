// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "codex-usage",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "CodexUsage",
            path: "Sources/CodexUsage"
        ),
    ]
)
