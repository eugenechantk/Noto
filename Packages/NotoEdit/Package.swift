// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotoEdit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotoEdit", targets: ["NotoEdit"]),
    ],
    targets: [
        // Pure logic — no UIKit/SwiftUI, no third-party deps. Models a document
        // edit (addition / edit / deletion), resolves text anchors to ranges,
        // coalesces them into diff hunks (blocks), and applies accepted blocks.
        .target(name: "NotoEdit"),
        .testTarget(name: "NotoEditTests", dependencies: ["NotoEdit"]),
    ]
)
