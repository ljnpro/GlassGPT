// swift-tools-version: 6.2

import PackageDescription

let boundaryTargets: [Target] = [
    .target(
        name: "ChatDomain",
        path: "Sources/ChatDomain"
    ),
    .target(
        name: "ChatPersistence",
        dependencies: ["ChatDomain"],
        path: "Sources/ChatPersistence"
    ),
    .target(
        name: "OpenAITransport",
        dependencies: ["ChatDomain"],
        path: "Sources/OpenAITransport"
    ),
    .target(
        name: "GeneratedFiles",
        dependencies: ["ChatDomain"],
        path: "Sources/GeneratedFiles"
    ),
    .target(
        name: "ChatRuntime",
        dependencies: [
            "ChatDomain",
            "ChatPersistence",
            "OpenAITransport",
            "GeneratedFiles"
        ],
        path: "Sources/ChatRuntime"
    ),
    .target(
        name: "ChatFeatures",
        dependencies: ["ChatRuntime"],
        path: "Sources/ChatFeatures"
    ),
    .target(
        name: "ChatUI",
        dependencies: ["ChatFeatures"],
        path: "Sources/ChatUI"
    ),
]

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
    targets: boundaryTargets + [
        .target(
            name: "NativeChat",
            dependencies: [
                "ChatDomain",
                "ChatPersistence",
                "OpenAITransport",
                "GeneratedFiles",
                "ChatRuntime",
                "ChatFeatures",
                "ChatUI",
            ],
            path: "ios",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NativeChatTests",
            dependencies: [
                "NativeChat",
                "ChatDomain",
                "ChatPersistence",
                "ChatRuntime",
                "ChatFeatures",
                "ChatUI",
                "OpenAITransport",
                "GeneratedFiles",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/NativeChatTests",
            exclude: ["__Snapshots__"]
        )
    ],
    swiftLanguageModes: [.v6]
)
