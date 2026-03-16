// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NativeChat",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "NativeChat",
            targets: ["NativeChat"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        )
    ],
    targets: [
        .target(
            name: "NativeChat",
            path: "ios",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NativeChatTests",
            dependencies: [
                "NativeChat",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/NativeChatTests"
        )
    ]
)
