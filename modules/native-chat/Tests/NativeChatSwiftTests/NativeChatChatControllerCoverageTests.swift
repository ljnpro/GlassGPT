import BackendClient
import BackendContracts
import ChatDomain
import Foundation
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatChatControllerCoverageTests {
    @Test func `chat controller handles signed out blocked and reset states`() async throws {
        let signedOut = try makeNativeChatHarness(signedIn: false).makeChatController()

        #expect(!signedOut.sendMessage(text: ""))
        #expect(!signedOut.sendMessage(text: "Hello"))
        #expect(signedOut.errorMessage == "Sign in with Apple in Settings to use chat.")

        let imageHarness = try makeNativeChatHarness(signedIn: true)
        let imageController = imageHarness.makeChatController()
        imageController.setCurrentConversation(makeHarnessConversation())
        imageController.selectedImageData = Data([0x01])
        #expect(imageController.sendMessage(text: ""))
        let imageTask = try #require(imageController.submissionTask)
        await imageTask.value
        #expect(imageHarness.client.sentMessages.last?.imageBase64 == "AQ==")

        let fileHarness = try makeNativeChatHarness(signedIn: true)
        let controller = fileHarness.makeChatController()
        controller.setCurrentConversation(makeHarnessConversation())
        controller.pendingAttachments = [
            FileAttachment(
                filename: "doc.pdf",
                fileSize: 4,
                fileType: "pdf",
                localData: Data([0x01, 0x02, 0x03, 0x04])
            )
        ]
        fileHarness.client.uploadBehavior = .immediateSuccess("file_chat_doc")
        #expect(controller.sendMessage(text: ""))
        let fileTask = try #require(controller.submissionTask)
        await fileTask.value
        #expect(fileHarness.client.uploadFileCalls.last?.filename == "doc.pdf")
        #expect(fileHarness.client.sentMessages.last?.fileIDs == ["file_chat_doc"])
        controller.pendingAttachments = []

        controller.isStreaming = true
        #expect(!controller.sendMessage(text: "Hello"))
        controller.isStreaming = false

        let attachment = FileAttachment(filename: "doc.pdf", fileType: "pdf")
        controller.pendingAttachments = [attachment]
        controller.removePendingAttachment(attachment)
        #expect(controller.pendingAttachments.isEmpty)

        controller.currentStreamingText = "text"
        controller.currentThinkingText = "thinking"
        controller.errorMessage = "error"
        controller.startNewConversation()
        #expect(controller.messages.isEmpty)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.errorMessage == nil)

        controller.stopGeneration()
        #expect(!controller.isStreaming)
    }

    @Test func `chat controller conversation state syncs and validates account ownership`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        let conversation = makeHarnessConversation()
        let foreignConversation = makeHarnessConversation(accountID: "other")

        controller.setCurrentConversation(conversation)
        controller.applyConversationConfiguration(
            ConversationConfiguration(model: .gpt5_4_pro, reasoningEffort: .high, serviceTier: .flex)
        )
        controller.persistVisibleConfiguration()
        #expect(conversation.model == ModelType.gpt5_4_pro.rawValue)
        #expect(conversation.serviceTierRawValue == ServiceTier.flex.rawValue)

        controller.messages = [makeBackendMessageSurface()]
        controller.syncMessages()
        #expect(controller.currentConversationID == conversation.id)

        #expect(!controller.applyLoadedConversation(foreignConversation))
        #expect(controller.errorMessage == "This conversation belongs to a different account.")
        #expect(controller.applyLoadedConversation(conversation))

        await controller.bootstrap()
        #expect(controller.currentConversationID != nil || controller.messages.isEmpty)
    }

    @Test func `chat controller detached streaming bubble follows live draft ownership`() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()

        controller.isStreaming = true
        controller.currentStreamingText = "Streaming"
        controller.liveFilePathAnnotations = [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "/tmp/report.md",
                filename: "report.md",
                startIndex: 0,
                endIndex: 4
            )
        ]
        #expect(controller.shouldShowDetachedStreamingBubble)

        controller.messages = [makeBackendMessageSurface(role: .assistant, content: "", isComplete: false)]
        #expect(controller.liveDraftMessageID != nil)
        #expect(!controller.shouldShowDetachedStreamingBubble)
    }

    @Test func `chat controller stream path applies live payloads and clears detached surface on completion`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        let conversation = makeHarnessConversation(serverID: "conv_chat_stream")
        controller.setCurrentConversation(conversation)
        controller.syncMessages()
        harness.client.detail = try makeChatConversationDetailSnapshot(
            conversationID: "conv_chat_stream",
            runID: "run_chat_stream",
            assistantContent: "Alpha Beta"
        )
        harness.client.streamEvents = try [
            SSEEvent(event: "thinking_delta", data: makeJSONString(["thinkingDelta": "Searching sources"]), id: nil),
            SSEEvent(
                event: "tool_call_update",
                data: makeJSONString([
                    "toolCall": [
                        "id": "tool_search",
                        "type": "web_search",
                        "status": "searching",
                        "queries": ["GlassGPT 5.1.2"]
                    ]
                ]),
                id: nil
            ),
            SSEEvent(
                event: "citations_update",
                data: makeJSONString([
                    "citations": [
                        [
                            "url": "https://example.com/plan",
                            "title": "Plan",
                            "startIndex": 0,
                            "endIndex": 5
                        ]
                    ]
                ]),
                id: nil
            ),
            SSEEvent(
                event: "file_path_annotations_update",
                data: makeJSONString([
                    "filePathAnnotations": [
                        [
                            "fileId": "file_plan",
                            "containerId": "sandbox_1",
                            "sandboxPath": "/tmp/beta-5-plan.md",
                            "filename": "beta-5-plan.md",
                            "startIndex": 6,
                            "endIndex": 14
                        ]
                    ]
                ]),
                id: nil
            ),
            SSEEvent(event: "status", data: makeJSONString(["visibleSummary": "Comparing sources"]), id: nil),
            SSEEvent(event: "delta", data: makeJSONString(["textDelta": "Alpha "]), id: nil),
            SSEEvent(event: "delta", data: makeJSONString(["textDelta": "Beta"]), id: nil),
            SSEEvent(event: "done", data: "{}", id: nil)
        ]

        await controller.streamOrPollRun(
            conversationServerID: "conv_chat_stream",
            runID: "run_chat_stream",
            selectionToken: controller.visibleSelectionToken
        )

        #expect(harness.client.fetchRunCallCount == 1)
        #expect(controller.messages.count == 2)
        #expect(controller.messages.last?.content == "Alpha Beta")
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.activeToolCalls.isEmpty)
        #expect(controller.liveCitations.isEmpty)
        #expect(controller.liveFilePathAnnotations.isEmpty)
        #expect(!controller.shouldShowDetachedStreamingBubble)
    }

    @Test func `chat controller falls back to polling when stream setup fails and still clears live surface`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        let conversation = makeHarnessConversation(serverID: "conv_chat_poll")
        controller.setCurrentConversation(conversation)
        controller.syncMessages()
        harness.client.detail = try makeChatConversationDetailSnapshot(
            conversationID: "conv_chat_poll",
            runID: "run_chat_poll",
            assistantContent: "Polling final answer"
        )
        harness.client.streamSetupError = .unacceptableStatusCode(401)
        harness.client.queuedRunResponses["run_chat_poll"] = [
            makeChatRunSummary(id: "run_chat_poll", status: .completed, summary: "Done")
        ]

        await controller.streamOrPollRun(
            conversationServerID: "conv_chat_poll",
            runID: "run_chat_poll",
            selectionToken: controller.visibleSelectionToken
        )

        #expect(harness.client.fetchRunCallCount == 1)
        #expect(controller.messages.last?.content == "Polling final answer")
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
        #expect(controller.activeToolCalls.isEmpty)
        #expect(controller.liveCitations.isEmpty)
        #expect(controller.liveFilePathAnnotations.isEmpty)
        #expect(!controller.shouldShowDetachedStreamingBubble)
    }

    @Test func `chat controller surfaces structured stream error messages instead of raw payload JSON`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let controller = harness.makeChatController()
        let conversation = makeHarnessConversation(serverID: "conv_chat_stream_error")
        controller.setCurrentConversation(conversation)
        controller.syncMessages()
        harness.client.detail = try makeChatConversationDetailSnapshot(
            conversationID: "conv_chat_stream_error",
            runID: "run_chat_stream_error",
            assistantContent: ""
        )
        harness.client.streamEvents = try [
            SSEEvent(
                event: "error",
                data: makeJSONString([
                    "code": "realtime_stream_unavailable",
                    "message": "Realtime stream became unavailable. Please retry.",
                    "phase": "relay"
                ]),
                id: nil
            )
        ]

        await controller.streamOrPollRun(
            conversationServerID: "conv_chat_stream_error",
            runID: "run_chat_stream_error",
            selectionToken: controller.visibleSelectionToken
        )

        #expect(harness.client.fetchRunCallCount == 1)
        #expect(controller.errorMessage == nil)
        #expect(controller.currentStreamingText.isEmpty)
        #expect(controller.currentThinkingText.isEmpty)
    }
}
