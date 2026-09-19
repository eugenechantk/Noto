// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoShareCapture",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoShareCapture", targets: ["NotoShareCapture"]),
    ],
    targets: [
        .target(name: "NotoShareCapture"),
        .testTarget(
            name: "NotoShareCaptureTests",
            dependencies: ["NotoShareCapture"]
        ),
    ]
)
