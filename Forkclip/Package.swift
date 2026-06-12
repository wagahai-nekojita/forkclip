// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Forkclip",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .executableTarget(
            name: "Forkclip",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ForkclipTests",
            dependencies: [
                "Forkclip",
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        ),
    ]
)
