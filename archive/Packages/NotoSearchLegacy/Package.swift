// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoSearchLegacy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoSearchLegacy", targets: ["NotoSearchLegacy"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
        .package(path: "../NotoDirtyTracker"),
        .package(path: "../NotoFTS5"),
        .package(path: "../NotoHNSW"),
        .package(path: "../NotoEmbedding"),
    ],
    targets: [
        .target(name: "NotoSearchLegacy", dependencies: [
            "NotoModels",
            "NotoCore",
            "NotoDirtyTracker",
            "NotoFTS5",
            "NotoHNSW",
            "NotoEmbedding",
        ]),
        .testTarget(
            name: "NotoSearchLegacyTests",
            dependencies: [
                "NotoSearchLegacy",
                "NotoModels",
                "NotoCore",
                "NotoDirtyTracker",
                "NotoFTS5",
                "NotoEmbedding",
                "NotoHNSW",
            ]
        ),
    ]
)
