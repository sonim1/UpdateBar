// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UpdateBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "updatebar", targets: ["UpdateBarCLI"]),
        .executable(name: "updatebar-menubar", targets: ["UpdateBarMenuBarApp"]),
        .library(name: "UpdateBarCore", targets: ["UpdateBarCore"]),
        .library(name: "UpdateBarMenuBar", targets: ["UpdateBarMenuBar"]),
        .library(name: "UpdateBarTestSupport", targets: ["UpdateBarTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "UpdateBarCLI",
            dependencies: [
                "UpdateBarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(name: "UpdateBarCore"),
        .target(
            name: "UpdateBarMenuBar",
            dependencies: ["UpdateBarCore"]
        ),
        .executableTarget(
            name: "UpdateBarMenuBarApp",
            dependencies: ["UpdateBarCore", "UpdateBarMenuBar"]
        ),
        .target(
            name: "UpdateBarTestSupport",
            dependencies: ["UpdateBarCore"]
        ),
        .testTarget(
            name: "UpdateBarCoreTests",
            dependencies: ["UpdateBarCore", "UpdateBarTestSupport"]
        ),
        .testTarget(
            name: "UpdateBarCLITests",
            dependencies: ["UpdateBarCore", "UpdateBarTestSupport"]
        ),
        .testTarget(
            name: "UpdateBarMenuBarTests",
            dependencies: ["UpdateBarCore", "UpdateBarMenuBar", "UpdateBarTestSupport"]
        )
    ]
)
