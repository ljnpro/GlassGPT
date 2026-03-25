import ChatDomain
import ChatPersistenceSwiftData
import ChatPresentation
import GeneratedFilesCore
import NativeChatUI
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct ViewHostingCoverageTests {
    @Test func `settings gateway snapshot matches phone light reference`() {
        let store = makeTestSettingsScreenStoreHarness(apiKey: "sk-hosted").store
        store.credentials.isAPIKeyValid = true
        store.defaults.cloudflareEnabled = true
        store.credentials.cloudflareHealthStatus = .remoteError("Gateway timeout")

        assertHostedSnapshot(
            named: "phone-light",
            testName: "testSettingsGatewaySnapshot",
            size: CGSize(width: 393, height: 1500),
            delay: 0.15
        ) {
            SettingsView(viewModel: store)
        }
    }

    @Test func `model selector snapshot matches phone light reference`() {
        assertHostedSnapshot(
            named: "phone-light",
            testName: "testModelSelectorSnapshot",
            size: snapshotVariant.canvasSize
        ) {
            SnapshotModelSelectorHost(variant: snapshotVariant)
        }
    }

    @Test func `chat snapshots cover empty and blocking overlay states`() throws {
        let emptyStore = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        assertHostedSnapshot(
            named: "empty-phone-light",
            testName: "testChatCoverageSnapshots",
            size: snapshotVariant.canvasSize,
            delay: 0.15
        ) {
            ChatView(viewModel: emptyStore)
        }

        let overlayStore = try makeTestChatScreenStore(
            apiKey: "",
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        overlayStore.isRestoringConversation = true
        overlayStore.isDownloadingFile = true
        assertHostedSnapshot(
            named: "overlay-phone-light",
            testName: "testChatCoverageSnapshots",
            size: snapshotVariant.canvasSize,
            delay: 0.15
        ) {
            ChatView(viewModel: overlayStore)
        }
    }

    @Test func `chat detached streaming snapshot matches phone light reference`() throws {
        let store = try makeDetachedStreamingChatStore()
        assertHostedSnapshot(
            named: "streaming-phone-light",
            testName: "testDetachedStreamingSnapshot",
            size: CGSize(width: 393, height: 1000),
            delay: 0.15
        ) {
            ChatView(viewModel: store)
        }
    }

    @Test func `agent snapshot matches phone light reference`() throws {
        let store = try makeSnapshotAgentScreenStore(hasAPIKey: true)
        let conversation = makeCompletedAgentConversationSamples(in: store)
        let expandedMessageIDs = Set(conversation.messages.map(\.id))

        assertHostedSnapshot(
            named: "agent-phone-light",
            testName: "testAgentCoverageSnapshot",
            size: snapshotVariant.canvasSize,
            delay: 0.15
        ) {
            AgentView(
                viewModel: store,
                initialExpandedTraceMessageIDs: expandedMessageIDs
            )
        }
    }

    @Test func `file preview snapshots cover image and PDF payloads`() throws {
        let imageURL = try makeSnapshotImageFile()
        assertHostedSnapshot(
            named: "image-phone-light",
            testName: "testFilePreviewSnapshots",
            size: snapshotVariant.canvasSize,
            delay: 0.25
        ) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: imageURL,
                    kind: .generatedImage,
                    displayName: "Generated Chart",
                    viewerFilename: "chart.png"
                )
            )
        }

        let pdfURL = try makeSnapshotPDFFile()
        assertHostedSnapshot(
            named: "pdf-phone-light",
            testName: "testFilePreviewSnapshots",
            size: snapshotVariant.canvasSize,
            delay: 0.25
        ) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: pdfURL,
                    kind: .generatedPDF,
                    displayName: "Quarterly Report",
                    viewerFilename: "report.pdf"
                )
            )
        }
    }

    @Test func `presentation components snapshot matches phone light reference`() {
        assertHostedSnapshot(
            named: "phone-light",
            testName: "testPresentationCoverageSnapshot",
            size: CGSize(width: 393, height: 420)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ThinkingView(
                    text: "First **reason** step, then confirm the release is stable.",
                    isLive: false,
                    externalIsExpanded: .constant(true)
                )
                TypingIndicator()
                CodeInterpreterIndicator()
                CodeInterpreterResultView(
                    toolCall: ToolCallInfo(
                        id: "ci_result",
                        type: .codeInterpreter,
                        status: .completed,
                        code: "print('release ok')",
                        results: ["release ok", "archive complete"]
                    )
                )
            }
            .padding()
        }
    }
}

@MainActor
private func makeDetachedStreamingChatStore() throws -> ChatController {
    let store = try makeTestChatScreenStore(
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
    )
    let conversation = Conversation(title: "Release Review")
    let userMessage = Message(role: .user, content: "Show the current status.", conversation: conversation)
    let assistantMessage = Message(
        role: .assistant,
        content: "Stored response",
        thinking: "Stored reasoning",
        conversation: conversation
    )

    conversation.messages = [userMessage, assistantMessage]
    store.currentConversation = conversation
    store.messages = [userMessage, assistantMessage]
    store.isStreaming = true
    store.isThinking = true
    store.thinkingPresentationState = .completed
    store.visibleSessionMessageID = UUID()
    store.currentThinkingText = "Checking the release pipeline and verifying the archive."
    store.currentStreamingText = "Archive complete. Uploading the build now."
    store.activeToolCalls = [
        ToolCallInfo(id: "ws_live", type: .webSearch, status: .searching, queries: ["release checklist"]),
        ToolCallInfo(
            id: "ci_done",
            type: .codeInterpreter,
            status: .completed,
            code: "print('release ok')",
            results: ["release ok", "upload complete"]
        )
    ]
    store.liveCitations = [URLCitation(
        url: "https://example.com/release",
        title: "Release Checklist",
        startIndex: 0,
        endIndex: 8
    )]
    store.errorMessage = "Connection lost. Retrying."
    return store
}

private let snapshotVariant = HostedSnapshotVariant.phoneLight

private enum HostedSnapshotVariant {
    case phoneLight

    var appTheme: AppTheme {
        .light
    }

    var canvasSize: CGSize {
        CGSize(width: 393, height: 852)
    }

    var safeArea: UIEdgeInsets {
        UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    var traits: UITraitCollection {
        UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = .compact
            $0.verticalSizeClass = .regular
            $0.displayScale = 3
            $0.userInterfaceStyle = .light
        })
    }

    func imageConfig(size: CGSize) -> ViewImageConfig {
        ViewImageConfig(
            safeArea: safeArea,
            size: size,
            traits: traits
        )
    }
}

@MainActor
private func assertHostedSnapshot(
    named name: String,
    testName: String,
    size: CGSize,
    delay: TimeInterval = 0,
    file: StaticString = #filePath,
    line: UInt = #line,
    @ViewBuilder content: () -> some View
) {
    let previousTheme = UserDefaults.standard.string(forKey: "appTheme")
    defer {
        if let previousTheme {
            UserDefaults.standard.set(previousTheme, forKey: "appTheme")
        } else {
            UserDefaults.standard.removeObject(forKey: "appTheme")
        }
    }

    UserDefaults.standard.set(snapshotVariant.appTheme.rawValue, forKey: "appTheme")

    let controller = UIHostingController(
        rootView: content()
            .preferredColorScheme(snapshotVariant.appTheme.colorScheme)
    )
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = .clear
    controller.preferredContentSize = size
    controller.view.bounds = CGRect(origin: .zero, size: size)
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    if delay > 0 {
        RunLoop.main.run(until: Date().addingTimeInterval(delay))
    }

    let recordMode: SnapshotTestingConfiguration.Record =
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? .all : .missing

    withSnapshotTesting(record: recordMode) {
        assertSnapshot(
            of: controller,
            as: .image(on: snapshotVariant.imageConfig(size: size)),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}

private struct SnapshotModelSelectorHost: View {
    let variant: HostedSnapshotVariant

    @State private var configuration = ConversationConfiguration(
        model: .gpt5_4_pro,
        reasoningEffort: .xhigh,
        backgroundModeEnabled: true,
        serviceTier: .flex
    )

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ModelSelectorSheet(
                    proModeEnabled: Binding(
                        get: { configuration.proModeEnabled },
                        set: { configuration.proModeEnabled = $0 }
                    ),
                    backgroundModeEnabled: $configuration.backgroundModeEnabled,
                    flexModeEnabled: Binding(
                        get: { configuration.flexModeEnabled },
                        set: { configuration.flexModeEnabled = $0 }
                    ),
                    reasoningEffort: $configuration.reasoningEffort,
                    onDone: {}
                )
                .padding(.horizontal, 16)
                .padding(.top, variant.safeArea.top + 56)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}
