// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoReadwiseSync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotoReadwiseSyncCore", targets: ["NotoReadwiseSyncCore"]),
        .executable(name: "noto-readwise-sync", targets: ["noto-readwise-sync"]),
    ],
    targets: [
        .target(name: "NotoReadwiseSyncCore"),
        .executableTarget(
            name: "noto-readwise-sync",
            dependencies: ["NotoReadwiseSyncCore"]
        ),
        .testTarget(
            name: "NotoReadwiseSyncCoreTests",
            dependencies: ["NotoReadwiseSyncCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

