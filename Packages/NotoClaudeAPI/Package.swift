// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotoClaudeAPI",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "NotoClaudeAPI",
            targets: ["NotoClaudeAPI"]
        )
    ],
    targets: [
        .target(
            name: "NotoClaudeAPI"
        ),
        .testTarget(
            name: "NotoClaudeAPITests",
            dependencies: ["NotoClaudeAPI"]
        )
    ]
)
