// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plynn",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "2.29.1"),
    ],
    targets: [
        .target(
            name: "PlynnKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
            ]),
        .executableTarget(
            name: "Plynn",
            dependencies: ["PlynnKit"]),
        .testTarget(
            name: "PlynnKitTests",
            dependencies: ["PlynnKit"],
            resources: [.copy("Fixtures")]),
    ]
)
