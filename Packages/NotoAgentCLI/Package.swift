// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoAgentCLI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotoAgentCore", targets: ["NotoAgentCore"]),
        .executable(name: "noto-agent", targets: ["noto-agent"]),
    ],
    dependencies: [
        .package(path: "../NotoVault"),
        .package(path: "../NotoSearch"),
    ],
    targets: [
        .target(
            name: "NotoAgentCore",
            dependencies: ["NotoVault", "NotoSearch"]
        ),
        .executableTarget(
            name: "noto-agent",
            dependencies: ["NotoAgentCore"]
        ),
        .testTarget(
            name: "NotoAgentCoreTests",
            dependencies: ["NotoAgentCore", "NotoVault"]
        ),
    ]
)
