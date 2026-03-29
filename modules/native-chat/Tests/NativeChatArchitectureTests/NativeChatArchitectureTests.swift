import BackendAuth
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import FilePreviewSupport
import GeneratedFilesCore
import NativeChat
import NativeChatUI
import SwiftData
import XCTest
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore

final class NativeChatArchitectureTests: XCTestCase {
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var workspaceRoot: URL {
        packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPackageManifestDeclaresBetaFiveTargets() throws {
        let manifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let requiredTargets = [
            "AppRouting",
            "BackendContracts",
            "BackendAuth",
            "BackendSessionPersistence",
            "BackendClient",
            "SyncProjection",
            "ConversationSyncApplication",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatProjectionPersistence",
            "GeneratedFilesCore",
            "GeneratedFilesCache",
            "FilePreviewSupport",
            "ChatPresentation",
            "ChatUIComponents",
            "NativeChatUI",
            "NativeChatBackendComposition",
            "NativeChatUITestSupport",
            "NativeChat"
        ]

        for target in requiredTargets {
            XCTAssertTrue(
                manifest.contains("name: \"\(target)\""),
                "Package.swift should declare \(target)"
            )
        }
    }

    func testSourceTargetsContainProductionSwift() {
        let targets = [
            "AppRouting",
            "BackendContracts",
            "BackendAuth",
            "BackendSessionPersistence",
            "BackendClient",
            "SyncProjection",
            "ConversationSyncApplication",
            "ChatDomain",
            "ChatPersistenceCore",
            "ChatProjectionPersistence",
            "GeneratedFilesCore",
            "GeneratedFilesCache",
            "FilePreviewSupport",
            "ChatPresentation",
            "ChatUIComponents",
            "NativeChatUI",
            "NativeChatBackendComposition",
            "NativeChat"
        ]
        let fileManager = FileManager.default

        for target in targets {
            let targetURL = packageRoot.appendingPathComponent("Sources/\(target)", isDirectory: true)
            XCTAssertTrue(fileManager.fileExists(atPath: targetURL.path), "Missing source target directory \(target)")

            let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: nil)
            let swiftFiles = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
            XCTAssertFalse(swiftFiles.isEmpty, "\(target) should include at least one production Swift file")
        }
    }

    func testNativeChatUmbrellaRoutesThroughBackendComposition() throws {
        let umbrella = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NativeChat/NativeChatRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            umbrella.contains("import NativeChatBackendComposition"),
            "NativeChat umbrella should route through NativeChatBackendComposition"
        )
        XCTAssertFalse(
            umbrella.contains("import NativeChatComposition"),
            "NativeChat umbrella must not import the legacy composition target"
        )
    }

    func testLegacyCleanPathDuplicatesWereDeletedFromNativeChatComposition() {
        let deletedPaths = [
            "Sources/NativeChatComposition/ContentView.swift",
            "Sources/NativeChatComposition/NativeChatRootView.swift",
            "Sources/NativeChatComposition/Projection/BackendChatView.swift",
            "Sources/NativeChatComposition/Projection/BackendAgentView.swift",
            "Sources/NativeChatComposition/Views/Chat/ChatView.swift",
            "Sources/NativeChatComposition/Views/Agent/AgentView.swift"
        ]

        for relativePath in deletedPaths {
            let path = packageRoot.appendingPathComponent(relativePath)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: path.path),
                "Legacy duplicate should be deleted: \(relativePath)"
            )
        }
    }

    func testUITestSupportLivesUnderSupportDirectory() {
        let supportRoot = packageRoot.appendingPathComponent("Support/NativeChatUITestSupport", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: supportRoot.path),
            "UITest support should live under Support/NativeChatUITestSupport"
        )
    }

    func testShippingAppMetadataNoLongerEmbedsCloudflareToken() throws {
        let infoPlist = try String(
            contentsOf: workspaceRoot.appendingPathComponent("ios/GlassGPT/Info.plist"),
            encoding: .utf8
        )

        XCTAssertFalse(
            infoPlist.contains("CloudflareAIGToken"),
            "Shipping app metadata must not embed CloudflareAIGToken"
        )
    }

    func testShippingAppMetadataUsesSplitBackendURLComponents() throws {
        let infoPlist = try String(
            contentsOf: workspaceRoot.appendingPathComponent("ios/GlassGPT/Info.plist"),
            encoding: .utf8
        )

        XCTAssertTrue(
            infoPlist.contains("<key>BackendBaseURLScheme</key>"),
            "Shipping app metadata should expose BackendBaseURLScheme"
        )
        XCTAssertTrue(
            infoPlist.contains("<key>BackendBaseURLHost</key>"),
            "Shipping app metadata should expose BackendBaseURLHost"
        )
        XCTAssertFalse(
            infoPlist.contains("<key>BackendBaseURL</key>"),
            "Shipping app metadata must not use a single URL key that can be truncated during xcconfig substitution"
        )
    }

    func testProjectBaseXcconfigAvoidsLiteralBackendURLValue() throws {
        let projectBase = try String(
            contentsOf: workspaceRoot.appendingPathComponent("ios/GlassGPT/Config/Project-Base.xcconfig"),
            encoding: .utf8
        )

        XCTAssertTrue(
            projectBase.contains("BACKEND_BASE_URL_SCHEME = https"),
            "Project base config should define the backend URL scheme separately"
        )
        XCTAssertTrue(
            projectBase.contains("BACKEND_BASE_URL_HOST = glassgpt-production.glassgpt.workers.dev"),
            "Project base config should define the backend URL host separately"
        )
        XCTAssertFalse(
            projectBase.contains("BACKEND_BASE_URL = https://"),
            "Project base config must not store a literal URL containing // because xcconfig treats // as a comment"
        )
    }

    @MainActor
    func testNewArchitectureModulesAreDirectlyCallable() throws {
        let settingsStore = SettingsStore(valueStore: InMemorySettingsValueStore())
        settingsStore.defaultModel = .gpt5_4_pro
        settingsStore.defaultEffort = .xhigh
        settingsStore.defaultServiceTier = .flex
        XCTAssertEqual(settingsStore.defaultConversationConfiguration.model, .gpt5_4_pro)
        XCTAssertEqual(settingsStore.defaultConversationConfiguration.reasoningEffort, .xhigh)
        XCTAssertEqual(settingsStore.defaultConversationConfiguration.serviceTier, .flex)

        let descriptor = GeneratedFileDescriptor(
            fileID: "file_chart",
            containerID: "ctr_1",
            filename: " chart.png ",
            mediaType: "image/png"
        )
        XCTAssertEqual(GeneratedFilePolicy.cacheBucket(for: descriptor), .image)
        XCTAssertEqual(GeneratedFilePolicy.openBehavior(for: descriptor), .imagePreview)
        XCTAssertEqual(
            GeneratedFilePreviewLoader.loadGeneratedImagePreview(from: URL(fileURLWithPath: "/tmp/missing.png")),
            .unavailable
        )

        let sessionStore = BackendSessionStore()
        XCTAssertFalse(sessionStore.isSignedIn)

        let container = try ModelContainer(
            for: Schema([Conversation.self, Message.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let root = NativeChatCompositionRoot(modelContext: ModelContext(container))
        let store = root.makeAppStore()
        XCTAssertNotNil(store.chatController)
        XCTAssertNotNil(store.agentController)
        XCTAssertNotNil(store.settingsPresenter)
        XCTAssertNotNil(store.historyPresenter)
        _ = NativeChatRootTabsView(title: "Architecture")
    }
}

private final class InMemorySettingsValueStore: SettingsValueStore {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        storage[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        storage[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
