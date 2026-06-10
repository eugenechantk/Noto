// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotoEmbedding",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "NotoEmbedding", targets: ["NotoEmbedding"]),
    ],
    targets: [
        .target(
            name: "NotoEmbedding",
            exclude: ["VendoredTokenizers/LICENSE-NOTICE.md"],
            resources: [
                .copy("Resources/tokenizer.json"),
                .copy("Resources/tokenizer_config.json"),
                .copy("Resources/GraniteEmbed_int8.mlpackage"),
            ]
        ),
        .testTarget(
            name: "NotoEmbeddingTests",
            dependencies: ["NotoEmbedding"],
            resources: [
                .copy("Resources/tokenizer_golden.json"),
                .copy("Resources/embed_golden.json"),
            ]
        ),
    ]
)
