// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TaskIsolatedEnv",
    platforms: [
        .macOS("15.0"), .iOS("18")
    ],
    products: [
        .library(
            name: "TaskIsolatedEnv",
            targets: ["TaskIsolatedEnv"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TaskIsolatedEnv",
            dependencies: []
        ),
        .testTarget(
            name: "TaskIsolatedEnvTests",
            dependencies: ["TaskIsolatedEnv"]
        )
    ]
)
