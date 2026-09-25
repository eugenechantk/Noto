// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoSocialMedia",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoSocialMedia", targets: ["NotoSocialMedia"]),
        .executable(name: "noto-share-media", targets: ["noto-share-media"]),
    ],
    dependencies: [
        .package(path: "../NotoShareCapture"),
    ],
    targets: [
        .target(
            name: "NotoSocialMedia",
            dependencies: ["NotoShareCapture"]
        ),
        .executableTarget(
            name: "noto-share-media",
            dependencies: ["NotoSocialMedia", "NotoShareCapture"]
        ),
        .testTarget(
            name: "NotoSocialMediaTests",
            dependencies: ["NotoSocialMedia", "NotoShareCapture"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
