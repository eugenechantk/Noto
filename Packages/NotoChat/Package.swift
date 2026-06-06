// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoChat",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoChat", targets: ["NotoChat"]),
    ],
    dependencies: [
        // Internal package only — no external/third-party dependencies.
        .package(path: "../NotoVault"),
    ],
    targets: [
        .target(
            name: "NotoChat",
            dependencies: ["NotoVault"]
        ),
        .testTarget(
            name: "NotoChatTests",
            dependencies: ["NotoChat"]
        ),
    ]
)
