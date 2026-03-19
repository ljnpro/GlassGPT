import ChatDomain
import ChatPersistenceSwiftData
import SnapshotTesting
import SwiftUI
import GeneratedFilesCore
import XCTest
@testable import NativeChatComposition
@testable import NativeChatUI

@MainActor
final class SnapshotViewTests: XCTestCase {
    override func invokeTest() {
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? .all : .missing

        withSnapshotTesting(record: recordMode) {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    // swiftlint:disable:next function_body_length
    func testChatSnapshots() throws {
        let emptyViewModel = try makeSnapshotChatScreenStore(hasAPIKey: false)
        assertViewSnapshots(named: "chat-empty") {
            ChatView(viewModel: emptyViewModel)
        }

        let conversationViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: conversationViewModel)
        assertViewSnapshots(named: "chat-standard") {
            ChatView(viewModel: conversationViewModel)
        }

        let richMarkdownViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeRichMarkdownConversationSamples(in: richMarkdownViewModel)
        assertViewSnapshots(named: "chat-rich-assistant-response") {
            ChatView(viewModel: richMarkdownViewModel)
        }

        let codeBlockViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeRichMarkdownCodeBlockConversationSamples(in: codeBlockViewModel)
        assertViewSnapshots(named: "chat-rich-assistant-response-code-block") {
            ChatView(viewModel: codeBlockViewModel)
        }

        let streamingViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: streamingViewModel)
        streamingViewModel.isStreaming = true
        streamingViewModel.isThinking = true
        streamingViewModel.currentThinkingText = "Gathering the deployment steps before finalizing the answer."
        streamingViewModel.currentStreamingText = "The release pipeline is running and the archive has completed successfully."
        streamingViewModel.activeToolCalls = [
            ToolCallInfo(
                id: "ci_1",
                type: .codeInterpreter,
                status: .interpreting,
                code: "print('build ok')",
                results: ["build ok"]
            )
        ]
        assertViewSnapshots(named: "chat-streaming") {
            ChatView(viewModel: streamingViewModel)
        }

        let errorViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: errorViewModel)
        errorViewModel.errorMessage = "Connection lost. Please check your network and try again."
        assertViewSnapshots(named: "chat-error") {
            ChatView(viewModel: errorViewModel)
        }

        let restoringViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: restoringViewModel)
        restoringViewModel.isRestoringConversation = true
        assertViewSnapshots(named: "chat-restoring") {
            ChatView(viewModel: restoringViewModel)
        }

        let recoveringViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: recoveringViewModel)
        if let liveDraft = recoveringViewModel.messages.last {
            recoveringViewModel.visibleSessionMessageID = liveDraft.id
            recoveringViewModel.draftMessage = liveDraft
        }
        recoveringViewModel.isStreaming = true
        recoveringViewModel.isRecovering = true
        recoveringViewModel.currentThinkingText = "Rebinding the in-progress response after app relaunch."
        recoveringViewModel.currentStreamingText = "Recovery stream connected. Replaying any missing deltas now."
        assertViewSnapshots(named: "chat-recovering") {
            ChatView(viewModel: recoveringViewModel)
        }
    }

    func testHistorySnapshots() throws {
        _ = try makeHistorySnapshotContainer()
        let store = makeHistoryScreenStore()
        assertViewSnapshots(named: "history-list") {
            HistoryView(store: store)
        }
    }

    func testSettingsSnapshots() {
        let viewModel = makeSettingsSnapshotViewModel()
        assertViewSnapshots(named: "settings") {
            SettingsView(viewModel: viewModel)
        }

        let gatewayViewModel = makeSettingsSnapshotViewModel()
        gatewayViewModel.apiKey = "sk-gateway"
        gatewayViewModel.cloudflareEnabled = true
        gatewayViewModel.cloudflareHealthStatus = .connected
        gatewayViewModel.generatedImageCacheSizeBytes = 12_800
        gatewayViewModel.generatedDocumentCacheSizeBytes = 65_536
        assertViewSnapshots(named: "settings-gateway") {
            SettingsView(viewModel: gatewayViewModel)
        }

        let unavailableGatewayViewModel = makeSettingsSnapshotViewModel()
        unavailableGatewayViewModel.cloudflareEnabled = true
        unavailableGatewayViewModel.cloudflareHealthStatus = .gatewayUnavailable
        unavailableGatewayViewModel.generatedImageCacheSizeBytes = 1_024
        unavailableGatewayViewModel.generatedDocumentCacheSizeBytes = 0
        assertViewSnapshots(named: "settings-gateway-unavailable") {
            SettingsView(viewModel: unavailableGatewayViewModel)
        }
    }

    func testModelSelectorPhoneLightSnapshot() {
        assertModelSelectorSnapshot(variant: .phoneLight)
    }

    func testModelSelectorPhoneDarkSnapshot() {
        assertModelSelectorSnapshot(variant: .phoneDark)
    }

    func testModelSelectorPadLightSnapshot() {
        assertModelSelectorSnapshot(variant: .padLight)
    }

    func testModelSelectorPadDarkSnapshot() {
        assertModelSelectorSnapshot(variant: .padDark)
    }

    func testFilePreviewSnapshots() throws {
        let imageURL = try makeSnapshotImageFile()
        assertViewSnapshots(named: "file-preview-image", delay: 0.25) {
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
        assertViewSnapshots(named: "file-preview-pdf", delay: 0.25) {
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

    // swiftlint:disable:next function_body_length
    func testPresentationComponentSnapshots() {
        assertViewSnapshots(named: "thinking-view", variants: [.phoneLight, .phoneDark]) {
            ThinkingView(
                text: "First **reason** step.\n\nThen evaluate `x^2` and finish.",
                isLive: false,
                externalIsExpanded: .constant(true)
            )
        }

        assertViewSnapshots(named: "thinking-indicator", variants: [.phoneLight, .phoneDark]) {
            ThinkingIndicator()
                .padding()
        }

        assertViewSnapshots(named: "code-block", variants: [.phoneLight, .phoneDark]) {
            CodeBlockView(
                language: "swift",
                code: """
                struct BuildReport {
                    let version: String
                    let passed: Bool
                }
                """,
                surfaceStyle: .standalone
            )
        }

        assertViewSnapshots(named: "code-interpreter-indicator", variants: [.phoneLight, .phoneDark]) {
            CodeInterpreterIndicator()
                .padding()
        }

        assertViewSnapshots(named: "code-interpreter-result", variants: [.phoneLight, .phoneDark]) {
            CodeInterpreterResultView(
                toolCall: ToolCallInfo(
                    id: "ci_result",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print('release ok')",
                    results: ["release ok", "archive complete"]
                )
            )
            .padding()
        }

        assertViewSnapshots(named: "file-attachments-row", variants: [.phoneLight, .phoneDark]) {
            FileAttachmentsRow(
                attachments: [
                    FileAttachment(
                        filename: "report.pdf",
                        fileSize: 12_800,
                        fileType: "pdf",
                        uploadStatus: .uploaded
                    ),
                    FileAttachment(
                        filename: "chart.png",
                        fileSize: 8_192,
                        fileType: "png",
                        uploadStatus: .uploading
                    ),
                    FileAttachment(
                        filename: "trace.txt",
                        fileSize: 256,
                        fileType: "txt",
                        uploadStatus: .failed
                    )
                ]
            )
            .padding()
        }

        assertViewSnapshots(named: "citation-links", variants: [.phoneLight, .phoneDark]) {
            CitationLinksView(
                citations: [
                    URLCitation(
                        url: "https://example.com/one",
                        title: "Release Notes",
                        startIndex: 0,
                        endIndex: 10
                    ),
                    URLCitation(
                        url: "https://example.com/two",
                        title: "Architecture Review",
                        startIndex: 11,
                        endIndex: 20
                    )
                ]
            )
            .padding()
        }
    }
}

@MainActor
private func assertModelSelectorSnapshot(variant: SnapshotTestThemeVariant) {
    assertViewSnapshots(
        named: "model-selector",
        variants: [variant],
        testName: "testModelSelectorSnapshots"
    ) {
        SnapshotModelSelectorHost(variant: variant)
    }
}

private struct SnapshotModelSelectorHost: View {
    let variant: SnapshotTestThemeVariant

    @State private var configuration = ConversationConfiguration(
        model: .gpt5_4_pro,
        reasoningEffort: .xhigh,
        backgroundModeEnabled: true,
        serviceTier: .flex
    )

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backgroundColor
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
                .padding(.top, topInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var topInset: CGFloat {
        variant.imageConfig.safeArea.top + 56
    }

    private var backgroundColor: Color {
        switch variant.appTheme {
        case .dark:
            return .black
        default:
            return Color(.systemBackground)
        }
    }
}
