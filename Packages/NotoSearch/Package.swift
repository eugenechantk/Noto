// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoSearch",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoSearch", targets: ["NotoSearch"]),
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
        .target(name: "NotoSearch", dependencies: [
            "NotoModels",
            "NotoCore",
            "NotoDirtyTracker",
            "NotoFTS5",
            "NotoHNSW",
            "NotoEmbedding",
        ]),
        .testTarget(
            name: "NotoSearchTests",
            dependencies: [
                "NotoSearch",
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
