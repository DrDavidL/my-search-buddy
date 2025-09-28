// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FinderCoreFFI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FinderCoreFFI", targets: ["FinderCoreFFI"]),
    ],
    targets: [
        .target(
            name: "FinderCoreShims",
            path: "Sources/FinderCoreShims",
            publicHeadersPath: "include"
        ),
        .target(
            name: "FinderCoreFFI",
            dependencies: ["FinderCoreShims"],
            path: "Sources/FinderCoreFFI",
            linkerSettings: [
                .linkedLibrary("finder_core"),
                .unsafeFlags([
                    "-L", "../target/debug",
                    "-L", "../target/release"
                ])
            ]
        ),
        .testTarget(
            name: "FinderCoreFFITests",
            dependencies: ["FinderCoreFFI"],
            path: "Tests/FinderCoreFFITests"
        ),
    ]
)
