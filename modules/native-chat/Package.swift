// swift-tools-version: 6.2

import PackageDescription

let boundaryTargets: [Target] = [
    .target(
        name: "ChatDomain",
        path: "Sources/ChatDomain"
    ),
    .target(
        name: "ChatPersistenceContracts",
        dependencies: ["ChatDomain"],
        path: "Sources/ChatPersistenceContracts"
    ),
    .target(
        name: "ChatPersistenceCore",
        dependencies: ["ChatDomain"],
        path: "Sources/ChatPersistenceCore"
    ),
    .target(
        name: "ChatPersistenceSwiftData",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceContracts",
            "ChatPersistenceCore"
        ],
        path: "Sources/ChatPersistenceSwiftData"
    ),
    .target(
        name: "OpenAITransport",
        dependencies: ["ChatDomain"],
        path: "Sources/OpenAITransport"
    ),
    .target(
        name: "GeneratedFilesCore",
        dependencies: ["ChatDomain"],
        path: "Sources/GeneratedFilesCore"
    ),
    .target(
        name: "GeneratedFilesInfra",
        dependencies: [
            "ChatDomain",
            "GeneratedFilesCore",
            "OpenAITransport"
        ],
        path: "Sources/GeneratedFilesInfra"
    ),
    .target(
        name: "ChatRuntimeModel",
        dependencies: ["ChatDomain"],
        path: "Sources/ChatRuntimeModel"
    ),
    .target(
        name: "ChatRuntimePorts",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceContracts",
            "GeneratedFilesCore",
            "ChatRuntimeModel"
        ],
        path: "Sources/ChatRuntimePorts"
    ),
    .target(
        name: "ChatRuntimeWorkflows",
        dependencies: [
            "ChatDomain",
            "ChatRuntimeModel",
            "ChatRuntimePorts"
        ],
        path: "Sources/ChatRuntimeWorkflows"
    ),
    .target(
        name: "ChatApplication",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceContracts",
            "ChatRuntimeModel",
            "ChatRuntimePorts",
            "ChatRuntimeWorkflows"
        ],
        path: "Sources/ChatApplication"
    ),
    .target(
        name: "ChatPresentation",
        dependencies: [
            "ChatDomain",
            "GeneratedFilesCore",
            "ChatApplication"
        ],
        path: "Sources/ChatPresentation"
    ),
    .target(
        name: "ChatUIComponents",
        path: "Sources/ChatUIComponents"
    ),
    .target(
        name: "NativeChatUI",
        dependencies: [
            "ChatDomain",
            "ChatPresentation",
            "ChatUIComponents"
        ],
        path: "Sources/NativeChatUI"
    ),
    .target(
        name: "NativeChatComposition",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceContracts",
            "ChatPersistenceCore",
            "ChatPersistenceSwiftData",
            "OpenAITransport",
            "GeneratedFilesCore",
            "GeneratedFilesInfra",
            "ChatRuntimeModel",
            "ChatRuntimePorts",
            "ChatRuntimeWorkflows",
            "ChatApplication",
            "ChatPresentation",
            "ChatUIComponents",
            "NativeChatUI"
        ],
        path: "Sources/NativeChatComposition"
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
                "ChatPersistenceContracts",
                "ChatPersistenceCore",
                "ChatPersistenceSwiftData",
                "OpenAITransport",
                "GeneratedFilesCore",
                "GeneratedFilesInfra",
                "ChatRuntimeModel",
                "ChatRuntimePorts",
                "ChatRuntimeWorkflows",
                "ChatApplication",
                "ChatPresentation",
                "ChatUIComponents",
                "NativeChatUI",
                "NativeChatComposition",
            ],
            path: "ios",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NativeChatArchitectureTests",
            dependencies: [
                "ChatDomain",
                "ChatPersistenceContracts",
                "ChatPersistenceCore",
                "ChatPersistenceSwiftData",
                "OpenAITransport",
                "GeneratedFilesCore",
                "GeneratedFilesInfra",
                "ChatRuntimeModel",
                "ChatRuntimePorts",
                "ChatRuntimeWorkflows",
                "ChatApplication",
                "ChatPresentation",
                "ChatUIComponents",
                "NativeChatUI",
                "NativeChatComposition"
            ],
            path: "Tests/NativeChatArchitectureTests"
        ),
        .testTarget(
            name: "NativeChatTests",
            dependencies: [
                "NativeChat",
                "ChatDomain",
                "ChatPersistenceContracts",
                "ChatPersistenceCore",
                "ChatPersistenceSwiftData",
                "ChatRuntimeModel",
                "ChatRuntimePorts",
                "ChatRuntimeWorkflows",
                "ChatApplication",
                "ChatPresentation",
                "ChatUIComponents",
                "OpenAITransport",
                "GeneratedFilesCore",
                "GeneratedFilesInfra",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/NativeChatTests",
            exclude: ["__Snapshots__"]
        )
    ],
    swiftLanguageModes: [.v6]
)
