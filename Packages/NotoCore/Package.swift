// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoCore", targets: ["NotoCore"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
    ],
    targets: [
        .target(name: "NotoCore", dependencies: ["NotoModels"]),
    ]
)
