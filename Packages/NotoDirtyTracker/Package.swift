// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoDirtyTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoDirtyTracker", targets: ["NotoDirtyTracker"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
    ],
    targets: [
        .target(name: "NotoDirtyTracker", dependencies: ["NotoModels", "NotoCore"]),
    ]
)
