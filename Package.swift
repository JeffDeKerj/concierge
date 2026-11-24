// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Concierge",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Concierge",
            path: "Sources/Concierge"
        ),
        .testTarget(
            name: "ConciergeTests",
            dependencies: ["Concierge"],
            path: "Tests/ConciergeTests"
        )
    ]
)
