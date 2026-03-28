// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotoAIChat",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NotoAIChat", targets: ["NotoAIChat"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
        .package(path: "../NotoDirtyTracker"),
        .package(path: "../NotoClaudeAPI"),
        .package(path: "../NotoSearch"),
    ],
    targets: [
        .target(name: "NotoAIChat", dependencies: [
            "NotoModels",
            "NotoCore",
            "NotoDirtyTracker",
            "NotoClaudeAPI",
            "NotoSearch",
        ]),
        .testTarget(
            name: "NotoAIChatTests",
            dependencies: ["NotoAIChat", "NotoModels", "NotoCore", "NotoDirtyTracker", "NotoClaudeAPI", "NotoSearch"]
        ),
    ]
)
