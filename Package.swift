// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexQ",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexQ", targets: ["CodexQ"])
    ],
    targets: [
        .executableTarget(
            name: "CodexQ",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CodexQTests",
            dependencies: ["CodexQ"]
        )
    ]
)
