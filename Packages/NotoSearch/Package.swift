// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoSearch",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoSearch", targets: ["NotoSearch"]),
    ],
    targets: [
        .target(name: "NotoSearch"),
        .testTarget(
            name: "NotoSearchTests",
            dependencies: ["NotoSearch"]
        ),
    ]
)
