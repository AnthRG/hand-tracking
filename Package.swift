// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HandKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HandCore", targets: ["HandCore"]),
        .library(name: "HandVision", targets: ["HandVision"]),
    ],
    targets: [
        .target(name: "HandCore"),
        .target(name: "HandVision", dependencies: ["HandCore"]),
        .executableTarget(name: "handprobe", dependencies: ["HandCore", "HandVision"]),
        .testTarget(name: "HandCoreTests", dependencies: ["HandCore"]),
    ]
)
