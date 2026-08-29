// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plynn",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PlynnKit"),
        .executableTarget(
            name: "Plynn",
            dependencies: ["PlynnKit"]),
        .testTarget(
            name: "PlynnKitTests",
            dependencies: ["PlynnKit"],
            resources: [.copy("Fixtures")]),
    ]
)
