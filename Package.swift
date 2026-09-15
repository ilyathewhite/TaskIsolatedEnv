// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TaskIsolatedEnv",
    platforms: [
        .macOS("15.0"), .iOS("17.6")
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
    ],
    swiftLanguageModes: [.v6]
)
