import BackendAuth
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ChatUIComponents
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

@Suite(.tags(.presentation))
@MainActor
struct NativeChatUIRenderingCoverageTests {
    @Test func `message input thinking and code interpreter surfaces cover live states`() throws {
        hostView(ThinkingIndicator())
        hostView(TypingIndicator())

        var expandedThinking: Bool? = true
        hostView(
            ThinkingView(
                text: "**Reasoning** with `code`",
                phase: .reasoning,
                externalIsExpanded: Binding(get: { expandedThinking }, set: { expandedThinking = $0 })
            )
        )
        hostView(
            ThinkingView(
                text: "Waiting for more context",
                phase: .waiting,
                externalIsExpanded: .constant(true)
            )
        )
        hostView(
            ThinkingView(
                text: "Completed reasoning",
                phase: .completed,
                externalIsExpanded: .constant(true)
            )
        )

        hostView(CodeBlockView(language: "swift", code: "func ship() { print(1) }"))
        hostView(CodeBlockView(language: "latex", code: "\\frac{1}{2}", surfaceStyle: .embedded))
        hostView(CodeBlockView(language: nil, code: "plain-text"))

        hostView(CodeInterpreterIndicator())
        let codeResultController = hostViewController(
            CodeInterpreterResultView(
                toolCall: ToolCallInfo(
                    id: "tool_1",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print('hello')",
                    results: ["hello", "world"]
                )
            )
        )
        tapControl(withIdentifier: "indicator.codeResult", in: codeResultController.view)
        drainMainRunLoop(0.2)

        var imageData: Data? = try Data(contentsOf: makeSnapshotImageFile())
        var attachments = [FileAttachment(filename: "spec.pdf", fileSize: 12, fileType: "pdf", uploadStatus: .pending)]
        var sendAttempts: [String] = []
        var stopCount = 0
        hostViewController(
            MessageInputBar(
                resetToken: UUID(),
                isStreaming: false,
                selectedImageData: Binding(get: { imageData }, set: { imageData = $0 }),
                pendingAttachments: Binding(get: { attachments }, set: { attachments = $0 }),
                onSend: { text in
                    sendAttempts.append(text)
                    return true
                },
                onStop: { stopCount += 1 },
                onPickImage: {},
                onPickDocument: {},
                onRemoveAttachment: { attachment in
                    attachments.removeAll { $0.id == attachment.id }
                }
            )
        )
        hostViewController(
            MessageInputBar(
                resetToken: UUID(),
                isStreaming: true,
                selectedImageData: .constant(nil),
                pendingAttachments: .constant([]),
                onSend: { _ in false },
                onStop: { stopCount += 1 },
                onPickImage: {},
                onPickDocument: {},
                onRemoveAttachment: { _ in }
            )
        )

        #expect(imageData != nil)
        #expect(sendAttempts.isEmpty)
        #expect(stopCount == 0)
    }

    @Test func `message bubble surfaces render live and attachment states`() throws {
        hostView(
            MessageBubble(
                message: makeBackendMessageSurface(
                    role: .assistant,
                    content: "Assistant body",
                    isComplete: false,
                    includeTrace: true
                ),
                liveContent: "Streaming content",
                liveThinking: "Live thinking",
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
        )
        try hostView(
            MessageBubble(
                message: BackendMessageSurface(
                    message: Message(
                        role: .user,
                        content: "Uploaded",
                        imageData: Data(contentsOf: makeSnapshotImageFile()),
                        fileAttachments: [FileAttachment(filename: "brief.md", fileSize: 5, fileType: "md", uploadStatus: .uploaded)]
                    )
                )
            )
        )
    }

    @Test func `backend chat projection views render empty active and selector states`() throws {
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)
        let signedInHarness = try makeNativeChatHarness(signedIn: true)

        hostView(BackendChatEmptyState(viewModel: signedOutHarness.makeChatController(), openSettings: {}))
        let chatController = signedInHarness.makeChatController()
        chatController.messages = [
            makeBackendMessageSurface(role: .user, content: "Question"),
            makeBackendMessageSurface(role: .assistant, content: "Answer", isComplete: true, includeTrace: true)
        ]
        chatController.isStreaming = true
        chatController.isThinking = true
        chatController.currentStreamingText = "Draft response"
        chatController.currentThinkingText = "Draft reasoning"
        chatController.errorMessage = "Temporary backend issue"

        hostView(
            BackendChatMessageList(
                viewModel: chatController,
                assistantBubbleMaxWidth: 520,
                streamingThinkingExpanded: .constant(true),
                openSettings: {}
            )
        )
        hostView(
            BackendChatComposer(
                viewModel: chatController,
                composerResetToken: UUID(),
                onSendAccepted: {},
                onPickImage: {},
                onPickDocument: {}
            )
        )
        hostView(
            BackendChatSelectorOverlay(
                viewModel: chatController,
                selectedTheme: .light,
                onDismiss: {}
            )
        )

        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
    }

    @Test func `backend agent projection views render empty active and overlay states`() throws {
        let signedOutHarness = try makeNativeChatHarness(signedIn: false)
        let signedInHarness = try makeNativeChatHarness(signedIn: true)

        hostView(BackendAgentEmptyState(viewModel: signedOutHarness.makeAgentController(), openSettings: {}))
        let agentController = signedInHarness.makeAgentController()
        let assistantMessage = makeBackendMessageSurface(role: .assistant, content: "Plan", isComplete: false, includeTrace: true)
        agentController.messages = [assistantMessage]
        agentController.isRunning = true
        agentController.isThinking = true
        agentController.currentStreamingText = "Synthesizing"
        agentController.currentThinkingText = "Comparing worker output"
        agentController.activeToolCalls = [ToolCallInfo(id: "code_live", type: .codeInterpreter, status: .interpreting)]
        agentController.liveCitations = [URLCitation(url: "https://example.com", title: "Citation", startIndex: 0, endIndex: 4)]
        agentController.processSnapshot = AgentProcessSnapshot(
            activity: .reviewing,
            currentFocus: "Review worker wave",
            leaderAcceptedFocus: "Review worker wave",
            leaderLiveStatus: "Reviewing",
            leaderLiveSummary: "Leader is reviewing"
        )
        agentController.errorMessage = "Retry pending"

        hostView(
            BackendAgentMessageList(
                viewModel: agentController,
                assistantBubbleMaxWidth: 520,
                liveSummaryExpanded: .constant(true),
                streamingThinkingExpanded: .constant(nil),
                expandedTraceMessageIDs: .constant([assistantMessage.id]),
                openSettings: {}
            )
        )
        hostView(
            BackendAgentComposer(
                viewModel: agentController,
                composerResetToken: UUID(),
                onSendAccepted: {},
                onPickImage: {},
                onPickDocument: {}
            )
        )
        hostView(
            BackendAgentSelectorOverlay(
                viewModel: agentController,
                selectedTheme: .light,
                onDismiss: {}
            )
        )

        try? FileManager.default.removeItem(at: signedOutHarness.cacheRoot)
        try? FileManager.default.removeItem(at: signedInHarness.cacheRoot)
    }
}
