// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoDigest",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoDigest", targets: ["NotoDigest"]),
    ],
    dependencies: [
        .package(path: "../NotoVault"),
    ],
    targets: [
        .target(
            name: "NotoDigest",
            dependencies: ["NotoVault"]
        ),
        .testTarget(
            name: "NotoDigestTests",
            dependencies: ["NotoDigest", "NotoVault"]
        ),
    ]
)
