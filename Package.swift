// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "window-layout",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WindowLayoutCore", targets: ["WindowLayoutCore"]),
        .executable(name: "window-layout", targets: ["WindowLayoutCLI"]),
        .executable(name: "window-layout-menu", targets: ["WindowLayoutMenu"]),
    ],
    targets: [
        .target(name: "WindowLayoutCore"),
        .executableTarget(
            name: "WindowLayoutCLI",
            dependencies: ["WindowLayoutCore"]
        ),
        .executableTarget(
            name: "WindowLayoutMenu",
            dependencies: ["WindowLayoutCore"]
        ),
        .testTarget(
            name: "WindowLayoutCoreTests",
            dependencies: ["WindowLayoutCore"]
        ),
    ]
)
