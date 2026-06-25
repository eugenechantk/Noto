// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoChat",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoChat", targets: ["NotoChat"]),
    ],
    dependencies: [
        // Internal packages only — no external/third-party dependencies.
        .package(path: "../NotoVault"),
        .package(path: "../NotoEdit"),
    ],
    targets: [
        .target(
            name: "NotoChat",
            dependencies: ["NotoVault", "NotoEdit"]
        ),
        .testTarget(
            name: "NotoChatTests",
            dependencies: ["NotoChat"]
        ),
    ]
)
