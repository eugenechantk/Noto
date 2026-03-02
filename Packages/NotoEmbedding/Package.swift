// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoEmbedding",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoEmbedding", targets: ["NotoEmbedding"]),
    ],
    targets: [
        .target(name: "NotoEmbedding"),
    ]
)
