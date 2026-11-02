// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TapeekCore",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "TapeekCore", targets: ["TapeekCore"])
    ],
    targets: [
        .target(name: "TapeekCore"),
        .executableTarget(
            name: "TapeekBench",
            dependencies: ["TapeekCore"]
        ),
        .testTarget(
            name: "TapeekCoreTests",
            dependencies: ["TapeekCore"]
        )
    ]
)
