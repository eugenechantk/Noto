// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoTodayNotes",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoTodayNotes", targets: ["NotoTodayNotes"]),
    ],
    dependencies: [
        .package(path: "../NotoModels"),
        .package(path: "../NotoCore"),
    ],
    targets: [
        .target(name: "NotoTodayNotes", dependencies: ["NotoModels", "NotoCore"]),
    ]
)
