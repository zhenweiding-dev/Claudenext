// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeNext",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeNext",
            path: "Sources/ClaudeNext",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
