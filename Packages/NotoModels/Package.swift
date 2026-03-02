// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoModels",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoModels", targets: ["NotoModels"]),
    ],
    targets: [
        .target(name: "NotoModels"),
    ]
)
