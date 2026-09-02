// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoTags",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoTags", targets: ["NotoTags"])
    ],
    targets: [
        .target(name: "NotoTags"),
        .testTarget(
            name: "NotoTagsTests",
            dependencies: ["NotoTags"]
        ),
    ]
)
