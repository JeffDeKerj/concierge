// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeAssistant",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAssistant",
            path: "Sources/ClaudeAssistant"
        ),
        .testTarget(
            name: "ClaudeAssistantTests",
            dependencies: ["ClaudeAssistant"],
            path: "Tests/ClaudeAssistantTests"
        )
    ]
)
