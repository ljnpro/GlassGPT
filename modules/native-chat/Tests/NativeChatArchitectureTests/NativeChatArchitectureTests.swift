import XCTest
import ChatPersistenceContracts
import ChatPersistenceCore
import ChatPersistenceSwiftData
import GeneratedFilesCore
import ChatRuntimeModel
import ChatRuntimePorts
import ChatRuntimeWorkflows
import ChatApplication
import ChatPresentation
import ChatUIComponents
import NativeChat
import NativeChatUI
import NativeChatComposition
import ChatDomain

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

    func testPackageManifestDeclaresFoundationTargets() throws {
        let manifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let requiredTargets = [
            "ChatPersistenceContracts",
            "ChatPersistenceCore",
            "ChatPersistenceSwiftData",
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
            "NativeChat",
            "NativeChatArchitectureTests",
        ]

        for target in requiredTargets {
            XCTAssertTrue(
                manifest.contains("name: \"\(target)\""),
                "Package.swift should declare \(target)"
            )
        }

        XCTAssertFalse(
            manifest.contains("name: \"NativeChatLegacy\""),
            "Package.swift should not retain the deprecated NativeChatLegacy target"
        )
    }

    func testNewSourceTargetsContainProductionSwift() throws {
        let targets = [
            "ChatPersistenceContracts",
            "ChatPersistenceCore",
            "ChatPersistenceSwiftData",
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
            "NativeChat",
        ]
        let fileManager = FileManager.default

        for target in targets {
            let targetURL = packageRoot.appendingPathComponent("Sources/\(target)", isDirectory: true)
            XCTAssertTrue(fileManager.fileExists(atPath: targetURL.path), "Missing source target directory \(target)")

            let swiftFiles = try fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(
                swiftFiles.isEmpty,
                "\(target) should include at least one production Swift file"
            )
        }
    }

    func testWorkflowAndLintCoverArchitectureGates() throws {
        let workflow = try String(
            contentsOf: workspaceRoot.appendingPathComponent(".github/workflows/ios.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(workflow.contains("./scripts/ci.sh architecture-tests"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh source-share"))
        XCTAssertTrue(workflow.contains("./scripts/ci.sh module-boundary"))

        let swiftlint = try String(
            contentsOf: workspaceRoot.appendingPathComponent(".swiftlint.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(swiftlint.contains("modules/native-chat/Sources"))
    }

    func testNativeChatUmbrellaNoLongerImportsLegacyImplementationDirectly() throws {
        let umbrella = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NativeChat/NativeChatRootView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(
            umbrella.contains("import NativeChatLegacy"),
            "NativeChat umbrella should re-export composition, not import NativeChatLegacy directly"
        )
        XCTAssertTrue(
            umbrella.contains("import NativeChatComposition"),
            "NativeChat umbrella should route through NativeChatComposition"
        )
    }

    func testLegacyIOSLayerIsDeleted() {
        let iosRoot = packageRoot.appendingPathComponent("ios", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: iosRoot.path),
            "modules/native-chat/ios must be deleted in the final architecture"
        )
    }

    func testNewArchitectureModulesAreDirectlyCallable() async throws {
        let conversation = StoredConversationSnapshot(
            id: UUID(),
            title: "  4.4.1 Baseline  ",
            modelIdentifier: "gpt-5.4",
            reasoningEffortIdentifier: "high",
            backgroundModeEnabled: true,
            serviceTierIdentifier: "default",
            updatedAt: Date()
        )
        XCTAssertEqual(conversation.title, "4.4.1 Baseline")
        XCTAssertTrue(conversation.hasCustomConfiguration)

        let valueStore = InMemorySettingsValueStore()
        let settings = SettingsStore(valueStore: valueStore)
        settings.defaultModel = .gpt5_4_pro
        XCTAssertEqual(settings.defaultModel, .gpt5_4_pro)
        XCTAssertTrue(SwiftDataPersistenceModuleReadiness().usesLegacyAdapters)

        let descriptor = GeneratedFileDescriptor(
            fileID: "file_chart",
            containerID: "ctr_1",
            filename: " chart.png ",
            mediaType: "image/png"
        )
        XCTAssertEqual(GeneratedFilePolicy.cacheBucket(for: descriptor), .image)
        XCTAssertEqual(GeneratedFilePolicy.openBehavior(for: descriptor), .imagePreview)

        let replyID = AssistantReplyID()
        let controller = await MainActor.run {
            ChatSceneController(
                registry: RuntimeRegistryActor(),
                preparationPort: ArchitectureTestPreparationPort()
            )
        }
        let startedReplyID = await controller.startReply(messageID: UUID(), conversationID: UUID())
        XCTAssertNotEqual(replyID, startedReplyID)

        let session = ReplySessionActor(
            initialState: ReplyRuntimeState(
                assistantReplyID: startedReplyID,
                messageID: UUID(),
                conversationID: UUID()
            )
        )
        let registry = RuntimeRegistryActor()
        await registry.register(session, for: startedReplyID)
        let registryContainsReply = await registry.contains(startedReplyID)
        XCTAssertTrue(registryContainsReply)

        let streamingText = RichTextAttributedStringBuilder.parseStreamingText("**Ship** 4.5.0")
        XCTAssertEqual(String(streamingText.characters), "Ship 4.5.0")

        let presenter = await MainActor.run {
            ChatPresenter(bootstrapPolicy: .live)
        }
        await MainActor.run {
            presenter.render(
                VisibleProjection(
                    conversationID: UUID(),
                    text: "Hello",
                    thinking: "Plan",
                    citations: [],
                    generatedFiles: []
                )
            )
            XCTAssertEqual(presenter.projection.text, "Hello")
            XCTAssertTrue(presenter.bootstrapPolicy.runLaunchTasks)

            let factory = NativeChatContainerFactory()
            _ = factory.makePresenter()
            _ = factory.makeRootView()
            _ = NativeChatRootTabsView(title: "Architecture")
        }

        struct TestClock: ClockPort {
            let now: Date
        }

        let clock = TestClock(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(clock.now.timeIntervalSince1970, 0)
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
}

@MainActor
private final class ArchitectureTestPreparationPort: SendMessagePreparationPort {
    func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        PreparedAssistantReply(
            apiKey: "sk-test",
            userMessageID: UUID(),
            draftMessageID: UUID(),
            conversationID: UUID(),
            requestMessages: [],
            requestModel: .gpt5_4_pro,
            requestEffort: .xhigh,
            requestUsesBackgroundMode: false,
            requestServiceTier: .standard,
            attachmentsToUpload: []
        )
    }

    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        attachments
    }

    func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID) {}
}
