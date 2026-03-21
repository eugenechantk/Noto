// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoVault",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoVault", targets: ["NotoVault"]),
    ],
    targets: [
        .target(name: "NotoVault"),
        .testTarget(
            name: "NotoVaultTests",
            dependencies: ["NotoVault"]
        ),
    ]
)
