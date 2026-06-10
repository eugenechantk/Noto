// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimRunner",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "SimRunnerKit"),
        .testTarget(
            name: "SimRunnerTests",
            dependencies: ["SimRunnerKit"],
            resources: [
                .copy("Resources/GraniteEmbed_int8.mlpackage"),
                .copy("Resources/sim_fixtures.json"),
            ]
        ),
    ]
)
