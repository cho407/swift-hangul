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
