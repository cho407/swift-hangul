// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-hangul",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HangulCore", targets: ["HangulCore"]),
        .library(name: "HangulSearch", targets: ["HangulSearch"]),
        .library(name: "HangulSearchable", targets: ["HangulSearchable"]),
    ],
    targets: [
        .target(
            name: "HangulCore",
            path: "Sources/HangulCore"
        ),
        .target(
            name: "HangulSearch",
            dependencies: ["HangulCore"],
            path: "Sources/HangulSearch"
        ),
        .target(
            name: "HangulSearchable",
            dependencies: ["HangulSearch"],
            path: "Sources/HangulSearchable"
        ),
        .testTarget(
            name: "HangulCoreTests",
            dependencies: ["HangulCore"],
            path: "Tests/HangulCoreTests"
        ),
        .testTarget(
            name: "HangulSearchTests",
            dependencies: ["HangulSearch"],
            path: "Tests/HangulSearchTests"
        ),
    ]
)
