import BackendAuth
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import Foundation
import GeneratedFilesCore
import PDFKit
import SwiftUI
import Testing
import UIKit
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

@Suite(.tags(.presentation))
@MainActor
struct NativeChatViewBodyEvaluationCoverageTests {
    @Test func `settings surfaces evaluate body across account defaults and sections`() async throws {
        let signedInHarness = try makeNativeChatHarness(signedIn: true)
        let signedOutSession = BackendSessionStore()
        let signedOutAccount = SettingsAccountStore(sessionStore: signedOutSession, client: UICoverageBackendRequester())

        signedInHarness.client.connectionStatus = ConnectionCheckDTO(
            backend: .healthy,
            auth: .healthy,
            openaiCredential: .invalid,
            sse: .degraded,
            checkedAt: .now,
            latencyMilliseconds: 18,
            errorSummary: "Realtime degraded"
        )
        await signedInHarness.settingsPresenter.account.checkConnection()

        let defaults = SettingsDefaultsStore(settingsStore: SettingsStore())
        defaults.defaultProModeEnabled = true
        defaults.defaultFlexModeEnabled = true
        defaults.defaultEffort = .high
        defaults.hapticEnabled = false

        let agentDefaults = AgentSettingsDefaultsStore(settingsStore: SettingsStore())
        agentDefaults.defaultFlexModeEnabled = true
        agentDefaults.defaultLeaderEffort = .xhigh
        agentDefaults.defaultWorkerEffort = .medium

        hostView(BodyEvaluatingView { SettingsAccountSection(viewModel: signedOutAccount).body })
        hostView(BodyEvaluatingView { SettingsAccountSection(viewModel: signedInHarness.settingsPresenter.account).body })
        hostView(
            BodyEvaluatingView {
                SettingsAccountStatusRow(
                    title: "Session",
                    statusText: "Signed In",
                    detailText: "Detail",
                    state: .healthy,
                    accessibilityIdentifier: "settings.account.session"
                ).body
            }
        )
        hostView(
            BodyEvaluatingView {
                SettingsHealthChip(
                    title: "Backend",
                    state: .degraded
                ).body
            }
        )
        hostView(BodyEvaluatingView { SettingsStatusIndicator(state: .healthy).body })
        hostView(BodyEvaluatingView { SettingsStatusIndicator(state: .invalid).body })
        hostView(BodyEvaluatingView { SettingsStatusIndicator(state: nil).body })
        hostView(BodyEvaluatingView { SettingsChatDefaultsSection(viewModel: defaults).body })
        hostView(BodyEvaluatingView { SettingsAppearanceSection(viewModel: defaults).body })
        hostView(BodyEvaluatingView { SettingsAgentDefaultsSection(viewModel: agentDefaults).body })
        hostView(BodyEvaluatingView { SettingsAgentDefaultsView(viewModel: agentDefaults).body })
        hostView(
            BodyEvaluatingView {
                SettingsAdaptiveToggleRow(
                    title: "Toggle",
                    accessibilityLabel: "Toggle",
                    accessibilityIdentifier: "toggle",
                    isOn: .constant(true)
                ).body
            }
        )
        hostView(
            BodyEvaluatingView {
                SettingsInlineReasoningEffortControl(
                    title: "Reasoning",
                    accessibilityLabel: "Reasoning",
                    accessibilityIdentifier: "reasoning",
                    selectedEffort: .constant(.medium),
                    availableEfforts: [.none, .low, .medium, .high, .xhigh]
                ).body
            }
        )

        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
    }

    @Test func `chat and agent projection sections evaluate body in empty and populated states`() throws {
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)
        let signedInHarness = try makeNativeChatHarness(signedIn: true)

        let emptyChat = signedOutHarness.makeChatController()
        let populatedChat = signedInHarness.makeChatController()
        populatedChat.messages = [
            makeBackendMessageSurface(role: .user, content: "Question"),
            makeBackendMessageSurface(role: .assistant, content: "Answer", isComplete: true, includeTrace: true)
        ]
        populatedChat.isStreaming = true
        populatedChat.currentStreamingText = "Draft"
        populatedChat.currentThinkingText = "Thinking"
        populatedChat.errorMessage = "Backend error"

        let emptyAgent = signedOutHarness.makeAgentController()
        let populatedAgent = signedInHarness.makeAgentController()
        populatedAgent.messages = [makeBackendMessageSurface(role: .assistant, content: "Plan", isComplete: false, includeTrace: true)]
        populatedAgent.isRunning = true
        populatedAgent.isThinking = true
        populatedAgent.currentStreamingText = "Synthesizing"
        populatedAgent.currentThinkingText = "Comparing"
        populatedAgent.activeToolCalls = [ToolCallInfo(id: "code", type: .codeInterpreter, status: .interpreting)]
        populatedAgent.liveCitations = [URLCitation(url: "https://example.com", title: "Citation", startIndex: 0, endIndex: 4)]
        populatedAgent.processSnapshot = AgentProcessSnapshot(
            activity: .reviewing,
            currentFocus: "Review",
            leaderAcceptedFocus: "Review",
            leaderLiveStatus: "Reviewing",
            leaderLiveSummary: "Leader review"
        )
        populatedAgent.errorMessage = "Retry pending"

        hostView(
            BodyEvaluatingView {
                BackendConversationTopBarSection(
                    viewModel: emptyChat,
                    onOpenSelector: {},
                    onStartNewConversation: {}
                ).body
            }
        )
        hostView(
            BodyEvaluatingView { BackendChatMessageList(
                viewModel: populatedChat,
                assistantBubbleMaxWidth: 520,
                streamingThinkingExpanded: .constant(true),
                openSettings: {}
            ).body }
        )
        hostView(
            BodyEvaluatingView {
                BackendConversationComposerSection(
                    viewModel: populatedChat,
                    composerResetToken: UUID(),
                    onSendAccepted: {},
                    onPickImage: {},
                    onPickDocument: {}
                ).body
            }
        )
        hostView(BodyEvaluatingView { BackendChatEmptyState(viewModel: emptyChat, openSettings: {}).body })
        hostView(BodyEvaluatingView { BackendChatSelectorOverlay(viewModel: populatedChat, selectedTheme: .light, onDismiss: {}).body })

        hostView(
            BodyEvaluatingView {
                BackendConversationTopBarSection(
                    viewModel: populatedAgent,
                    onOpenSelector: {},
                    onStartNewConversation: {}
                ).body
            }
        )
        hostView(
            BodyEvaluatingView { BackendAgentMessageList(
                viewModel: populatedAgent,
                assistantBubbleMaxWidth: 520,
                liveSummaryExpanded: .constant(true),
                streamingThinkingExpanded: .constant(nil),
                expandedTraceMessageIDs: .constant([populatedAgent.messages[0].id]),
                openSettings: {}
            ).body }
        )
        hostView(
            BodyEvaluatingView {
                BackendConversationComposerSection(
                    viewModel: populatedAgent,
                    composerResetToken: UUID(),
                    onSendAccepted: {},
                    onPickImage: {},
                    onPickDocument: {}
                ).body
            }
        )
        hostView(BodyEvaluatingView { BackendAgentEmptyState(viewModel: emptyAgent, openSettings: {}).body })
        hostView(BodyEvaluatingView { BackendAgentSelectorOverlay(viewModel: populatedAgent, selectedTheme: .light, onDismiss: {}).body })

        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
    }

    @Test func `message bubble and preview surfaces evaluate computed presentation states`() throws {
        let assistantBubble = MessageBubble(
            message: makeBackendMessageSurface(
                role: .assistant,
                content: "Assistant",
                isComplete: false,
                includeTrace: true
            ),
            liveContent: "Streaming",
            liveThinking: "Reasoning",
            activeToolCalls: [
                ToolCallInfo(id: "web", type: .webSearch, status: .searching),
                ToolCallInfo(id: "file", type: .fileSearch, status: .fileSearching),
                ToolCallInfo(id: "code", type: .codeInterpreter, status: .completed, code: "print(1)", results: ["1"])
            ],
            liveCitations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
            liveFilePathAnnotations: [
                FilePathAnnotation(
                    fileId: "file_1",
                    containerId: "container_1",
                    sandboxPath: "/tmp/report.pdf",
                    filename: "report.pdf",
                    startIndex: 0,
                    endIndex: 4
                )
            ],
            showsRecoveryIndicator: true,
            isLiveThinking: true,
            liveThinkingPresentationState: .reasoning
        )
        #expect(assistantBubble.displayedContent == "Streaming")
        #expect(assistantBubble.displayedThinking == "Reasoning")
        #expect(assistantBubble.displayedToolCalls.count == 3)
        #expect(assistantBubble.displayedThinkingPresentationState == .reasoning)
        #expect(assistantBubble.displayedCitations.count == 1)
        #expect(assistantBubble.displayedFilePathAnnotations.count == 1)
        #expect(assistantBubble.isDisplayingLiveAssistantState)
        hostView(assistantBubble)

        let userProjectionMessage = try Message(
            role: .user,
            content: "Uploaded",
            imageData: Data(contentsOf: makeSnapshotImageFile()),
            fileAttachments: [
                FileAttachment(filename: "brief.md", fileSize: 5, fileType: "md", uploadStatus: .uploaded)
            ]
        )
        let userBubble = MessageBubble(message: BackendMessageSurface(message: userProjectionMessage))
        #expect(userBubble.displayedContent == "Uploaded")
        #expect(userBubble.displayedThinking == nil)
        hostView(userBubble)

        let imageURL = try makeSnapshotImageFile()
        let pdfURL = try makeSnapshotPDFFile()

        let imageSheet = makeImagePreviewSheetForCoverage(imageURL: imageURL)
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.content })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.generatedImageViewer })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.imageTopBar })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.imageBottomBar })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.closeButton })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.downloadButton })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.bottomShareButton })
        hostView(FilePreviewComputedView(sheet: imageSheet) { $0.saveSuccessHUD })
        _ = imageSheet.saveErrorBinding

        let pdfSheet = makePDFPreviewSheetForCoverage(pdfURL: pdfURL)
        hostView(FilePreviewComputedView(sheet: pdfSheet) { $0.content })
        hostView(FilePreviewComputedView(sheet: pdfSheet) { $0.generatedPDFViewer })
        hostView(FilePreviewComputedView(sheet: pdfSheet) { $0.pdfTopBar })
        hostView(FilePreviewComputedView(sheet: pdfSheet) { $0.pdfShareButton })
        hostView(FilePreviewComputedView(sheet: pdfSheet) { $0.titleText })
    }
}

private struct FilePreviewComputedView<Content: View>: View {
    let sheet: FilePreviewSheet
    let builder: (FilePreviewSheet) -> Content

    var body: some View {
        builder(sheet)
    }
}

private struct BodyEvaluatingView<Content: View>: View {
    let builder: () -> Content

    var body: some View {
        builder()
    }
}

@MainActor
private func makeImagePreviewSheetForCoverage(imageURL: URL) -> FilePreviewSheet {
    FilePreviewSheet(
        previewItem: FilePreviewItem(
            url: imageURL,
            kind: .generatedImage,
            displayName: "Image",
            viewerFilename: "image.png"
        ),
        stateSeed: .init(
            saveError: "Unable to save",
            imagePreviewState: .error("Image failed"),
            showSaveSuccessHUD: true
        )
    )
}

@MainActor
private func makePDFPreviewSheetForCoverage(pdfURL: URL) -> FilePreviewSheet {
    FilePreviewSheet(
        previewItem: FilePreviewItem(
            url: pdfURL,
            kind: .generatedPDF,
            displayName: "PDF",
            viewerFilename: "report.pdf"
        ),
        isDismissPending: true,
        stateSeed: .init(pdfPreviewState: .error("PDF failed"))
    )
}
