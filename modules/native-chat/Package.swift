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
    targets: [
        .target(
            name: "NativeChat",
            path: "ios",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
