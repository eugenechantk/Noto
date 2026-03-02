// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoFTS5",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoFTS5", targets: ["NotoFTS5"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
        .package(path: "../NotoDirtyTracker"),
    ],
    targets: [
        .target(name: "NotoFTS5", dependencies: ["NotoModels", "NotoCore", "NotoDirtyTracker"]),
        .testTarget(
            name: "NotoFTS5Tests",
            dependencies: ["NotoFTS5", "NotoModels", "NotoCore", "NotoDirtyTracker"]
        ),
    ]
)
