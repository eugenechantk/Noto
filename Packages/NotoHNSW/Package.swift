// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoHNSW",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoHNSW", targets: ["NotoHNSW"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
        .package(path: "../NotoDirtyTracker"),
        .package(path: "../NotoEmbedding"),
        // USearch SPM will be added later:
        // .package(url: "https://github.com/unum-cloud/usearch", from: "2.0.0"),
    ],
    targets: [
        .target(name: "NotoHNSW", dependencies: [
            "NotoModels",
            "NotoCore",
            "NotoDirtyTracker",
            "NotoEmbedding",
            // "USearch",  // uncomment when USearch SPM is added
        ]),
    ]
)
