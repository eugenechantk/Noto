// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoLinkPreview",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoLinkPreview", targets: ["NotoLinkPreview"]),
    ],
    targets: [
        .target(
            name: "NotoLinkPreview",
            linkerSettings: [
                .linkedFramework("LinkPresentation"),
            ]
        ),
        .testTarget(
            name: "NotoLinkPreviewTests",
            dependencies: ["NotoLinkPreview"]
        ),
    ]
)
