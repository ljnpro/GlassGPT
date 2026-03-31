// swift-tools-version: 6.2

import PackageDescription

let boundaryTargets: [Target] = [
    .target(
        name: "AppRouting",
        dependencies: ["ChatDomain"],
        path: "Sources/AppRouting"
    ),
    .target(
        name: "BackendContracts",
        path: "Sources/BackendContracts"
    ),
    .target(
        name: "BackendAuth",
        dependencies: ["BackendContracts"],
        path: "Sources/BackendAuth"
    ),
    .target(
        name: "BackendSessionPersistence",
        dependencies: ["BackendAuth", "ChatPersistenceCore"],
        path: "Sources/BackendSessionPersistence"
    ),
    .target(
        name: "BackendClient",
        dependencies: ["BackendContracts", "BackendAuth", "ChatPersistenceCore"],
        path: "Sources/BackendClient"
    ),
    .target(
        name: "SyncProjection",
        dependencies: ["BackendContracts"],
        path: "Sources/SyncProjection"
    ),
    .target(
        name: "ConversationSyncApplication",
        dependencies: [
            "BackendContracts",
            "BackendAuth",
            "BackendClient",
            "SyncProjection",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatProjectionPersistence"
        ],
        path: "Sources/ConversationSyncApplication"
    ),
    .target(
        name: "ChatDomain",
        path: "Sources/ChatDomain",
        resources: [.process("ChatDomain.docc")]
    ),
    .target(
        name: "ChatPersistenceCore",
        dependencies: ["ChatDomain"],
        path: "Sources/ChatPersistenceCore"
    ),
    .target(
        name: "ChatPersistenceModels",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceCore"
        ],
        path: "Sources/ChatPersistenceModels"
    ),
    .target(
        name: "ChatPersistenceSwiftData",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatPersistenceModels"
        ],
        path: "Sources/ChatPersistenceSwiftData"
    ),
    .target(
        name: "ChatProjectionPersistence",
        dependencies: [
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatPersistenceModels"
        ],
        path: "Sources/ChatProjectionPersistence"
    ),
    .target(
        name: "GeneratedFilesCache",
        dependencies: ["GeneratedFilesCore"],
        path: "Sources/GeneratedFilesCache"
    ),
    .target(
        name: "FilePreviewSupport",
        dependencies: ["GeneratedFilesCore"],
        path: "Sources/FilePreviewSupport"
    ),
    .target(
        name: "GeneratedFilesCore",
        dependencies: ["ChatDomain"],
        path: "Sources/GeneratedFilesCore"
    ),
    .target(
        name: "ChatPresentation",
        dependencies: [
            "BackendAuth",
            "BackendClient",
            "BackendContracts",
            "ChatDomain",
            "ChatPersistenceCore",
            "GeneratedFilesCore",
            "GeneratedFilesCache"
        ],
        path: "Sources/ChatPresentation"
    ),
    .target(
        name: "ConversationSurfaceLogic",
        dependencies: ["ChatDomain"],
        path: "Sources/ConversationSurfaceLogic"
    ),
    .target(
        name: "ChatUIComponents",
        dependencies: ["ConversationSurfaceLogic"],
        path: "Sources/ChatUIComponents",
        resources: [
            .process("Resources")
        ]
    ),
    .target(
        name: "NativeChatUI",
        dependencies: [
            "ConversationSurfaceLogic",
            "ChatDomain",
            "ChatPresentation",
            "ChatUIComponents",
            "FilePreviewSupport"
        ],
        path: "Sources/NativeChatUI"
    ),
    .target(
        name: "NativeChatBackendCore",
        dependencies: [
            "AppRouting",
            "BackendAuth",
            "BackendSessionPersistence",
            "BackendClient",
            "BackendContracts",
            "ConversationSyncApplication",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatProjectionPersistence",
            "ChatPresentation",
            "ChatUIComponents",
            "GeneratedFilesCore",
            "GeneratedFilesCache"
        ],
        path: "Sources/NativeChatBackendCore"
    ),
    .target(
        name: "NativeChatBackendComposition",
        dependencies: [
            "NativeChatBackendCore",
            "ChatDomain",
            "ChatUIComponents",
            "NativeChatUI",
            "GeneratedFilesCore"
        ],
        path: "Sources/NativeChatBackendComposition",
        resources: [.process("Resources")]
    ),
    .target(
        name: "NativeChat",
        dependencies: [
            "ChatProjectionPersistence",
            "NativeChatBackendComposition"
        ],
        path: "Sources/NativeChat"
    ),
    .target(
        name: "NativeChatUITestSupport",
        dependencies: [
            "BackendSessionPersistence",
            "ChatPersistenceCore",
            "ChatPersistenceSwiftData",
            "NativeChatBackendCore",
            "NativeChatBackendComposition"
        ],
        path: "Support/NativeChatUITestSupport"
    )
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
        ),
        .library(
            name: "NativeChatUITestSupport",
            targets: ["NativeChatUITestSupport"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        )
    ],
    targets: boundaryTargets + [
        .testTarget(
            name: "NativeChatArchitectureTests",
            dependencies: [
                "BackendContracts",
                "BackendAuth",
                "ChatPersistenceCore",
                "ChatProjectionPersistence",
                "GeneratedFilesCore",
                "FilePreviewSupport",
                "ChatPresentation",
                "ConversationSurfaceLogic",
                "ChatUIComponents",
                "NativeChatBackendCore",
                "NativeChatUI",
                "NativeChatBackendComposition",
                "NativeChat",
                "NativeChatUITestSupport"
            ],
            path: "Tests/NativeChatArchitectureTests"
        ),
        .testTarget(
            name: "NativeChatSwiftTests",
            dependencies: [
                "ChatDomain",
                "BackendContracts",
                "BackendAuth",
                "BackendClient",
                "BackendSessionPersistence",
                "SyncProjection",
                "ConversationSyncApplication",
                "ChatPersistenceCore",
                "ChatPersistenceSwiftData",
                "ChatProjectionPersistence",
                "ChatPresentation",
                "ConversationSurfaceLogic",
                "ChatUIComponents",
                "FilePreviewSupport",
                "NativeChatBackendCore",
                "NativeChatUI",
                "GeneratedFilesCore",
                "GeneratedFilesCache",
                "NativeChatUITestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/NativeChatSwiftTests",
            exclude: ["__Snapshots__"]
        ),
        .testTarget(
            name: "NativeChatTests",
            dependencies: [
                "ChatDomain",
                "BackendContracts",
                "BackendAuth",
                "BackendClient",
                "ConversationSyncApplication",
                "ChatPersistenceCore",
                "ChatProjectionPersistence",
                "ChatPresentation",
                "GeneratedFilesCore",
                "GeneratedFilesCache",
                "ConversationSurfaceLogic",
                "NativeChatBackendCore",
                "NativeChatBackendComposition",
                "NativeChatUI",
                "NativeChatUITestSupport",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/NativeChatTests",
            exclude: ["__Snapshots__"]
        )
    ],
    swiftLanguageModes: [.v6]
)
