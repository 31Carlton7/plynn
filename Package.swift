// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlynnSpike",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
    ],
    targets: [
        .target(
            name: "PlynnSpikeKit",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .executableTarget(
            name: "PlynnSpike",
            dependencies: ["PlynnSpikeKit"]),
        .testTarget(
            name: "PlynnSpikeKitTests",
            dependencies: ["PlynnSpikeKit"],
            resources: [.copy("Fixtures")]),
    ]
)
