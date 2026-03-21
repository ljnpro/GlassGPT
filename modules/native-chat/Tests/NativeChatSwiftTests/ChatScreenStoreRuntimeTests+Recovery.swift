import ChatApplication
import ChatDomain
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

// MARK: - Recovery and Prefetch Tests

extension ChatScreenStoreRuntimeTests {
    @Test func `recover response visible session resumes streaming and finalizes through store API`() async throws {
        let streamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("Recovered via stream"),
                .completed("", "Recovered reasoning", nil)
            ]]
        )
        let transport = StubOpenAITransport()
        let resumeURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_stream_resume")
        )
        try await transport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: resumeURL
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Manual Recovery")
        let draft = makeIncompleteDraft(
            conversation: conversation,
            responseId: "resp_stream_resume",
            lastSequenceNumber: 7,
            usedBackgroundMode: true
        )
        conversation.messages.append(draft)
        store.modelContext.insert(draft)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [draft]
        store.syncConversationProjection()

        store.recoverResponse(
            messageId: draft.id,
            responseId: "resp_stream_resume",
            preferStreamingResume: true,
            visible: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        try assertRecoveredMessage(in: store, content: "Recovered via stream", thinking: "Recovered reasoning")
        let requestedPaths = await transport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_stream_resume"])
        #expect(streamClient.recordedRequests.count == 1)
    }

    @Test func `recover response404 uses fallback and clears visible runtime state`() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let transport = StubOpenAITransport()
        let missingURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_missing")
        )
        await transport.enqueue(
            data: Data("gone".utf8),
            statusCode: 404,
            url: missingURL
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "404 Recovery")
        let draft = makeIncompleteDraft(
            conversation: conversation,
            content: "Partial response",
            thinking: "Keep this reasoning",
            responseId: "resp_missing",
            lastSequenceNumber: 5,
            usedBackgroundMode: true
        )
        conversation.messages.append(draft)
        store.modelContext.insert(draft)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [draft]
        store.syncConversationProjection()

        store.recoverResponse(
            messageId: draft.id,
            responseId: "resp_missing",
            preferStreamingResume: true,
            visible: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        try assertRecoveredMessage(in: store, content: "Partial response", thinking: "Keep this reasoning")
        #expect(store.errorMessage == "This response is no longer resumable.")
        let requestedPaths = await transport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_missing"])
    }

    @Test func `start new chat cancels tracked generated file prefetch`() async throws {
        let fileDownloadTransport = SlowGeneratedFileDownloadTransport()
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider()
        let fileDownloadService = FileDownloadService(
            configurationProvider: configurationProvider,
            transport: fileDownloadTransport
        )
        let store = try makeTestChatScreenStore(
            configurationProvider: configurationProvider,
            fileDownloadService: fileDownloadService,
            streamClient: QueuedOpenAIStreamClient(scriptedStreams: [])
        )
        let conversation = try seedConversation(in: store, title: "Generated Prefetch")
        let message = Message(
            role: .assistant,
            content: "Finished",
            conversation: conversation,
            responseId: "resp_prefetch",
            filePathAnnotations: [
                FilePathAnnotation(
                    fileId: "file_prefetch",
                    containerId: "ctr_prefetch",
                    sandboxPath: "sandbox:/mnt/data/report.pdf",
                    filename: "report.pdf",
                    startIndex: 0,
                    endIndex: 10
                )
            ]
        )
        conversation.messages.append(message)
        store.modelContext.insert(message)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [message]

        store.fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)

        try await waitUntilAsync {
            await fileDownloadTransport.requestCount() == 1
        }

        store.conversationCoordinator.startNewChat()

        try await waitUntilAsync {
            await fileDownloadTransport.cancellationCount() == 1
        }
    }

    @Test func `recover response invisible polling finalizes message without binding visible session`() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let transport = StubOpenAITransport()
        let hiddenResumeURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_hidden_resume")
        )
        try await transport.enqueue(
            data: makeFetchResponseData(
                status: .completed,
                text: "Recovered via polling",
                thinking: "Recovered hidden reasoning"
            ),
            url: hiddenResumeURL
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Invisible Recovery")
        let draft = makeIncompleteDraft(
            conversation: conversation,
            responseId: "resp_hidden_resume",
            lastSequenceNumber: 2,
            usedBackgroundMode: false
        )
        conversation.messages.append(draft)
        store.modelContext.insert(draft)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [draft]
        store.syncConversationProjection()

        store.recoverResponse(
            messageId: draft.id,
            responseId: "resp_hidden_resume",
            preferStreamingResume: false,
            visible: false
        )

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        try assertRecoveredMessage(in: store, content: "Recovered via polling", thinking: "Recovered hidden reasoning")
        let requestedPaths = await transport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_hidden_resume"])
        #expect(streamClient.recordedRequests.isEmpty)
    }

    @Test func `recover response clears stale active tool calls when terminal fetch omits them`() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let transport = StubOpenAITransport()
        let resumeURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_clear_tools")
        )
        try await transport.enqueue(
            data: makeFetchResponseData(
                status: .completed,
                text: "Recovered without tool metadata",
                thinking: "Recovered cleanly"
            ),
            url: resumeURL
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Clear Stale Tool Calls")
        let draft = makeIncompleteDraft(
            conversation: conversation,
            content: "Partial response",
            responseId: "resp_clear_tools",
            lastSequenceNumber: 3,
            usedBackgroundMode: true
        )
        MessagePayloadStore.setToolCalls(
            [ToolCallInfo(id: "ws_1", type: .webSearch, status: .searching)],
            on: draft
        )
        conversation.messages.append(draft)
        store.modelContext.insert(draft)
        try store.modelContext.save()

        store.currentConversation = conversation
        store.messages = [draft]
        store.syncConversationProjection()

        store.recoverResponse(
            messageId: draft.id,
            responseId: "resp_clear_tools",
            preferStreamingResume: false,
            visible: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        let recovered = try #require(latestAssistantMessage(in: store))
        #expect(recovered.content == "Recovered without tool metadata")
        #expect(recovered.toolCalls.isEmpty)
    }
}

// MARK: - Recovery Helpers

extension ChatScreenStoreRuntimeTests {
    func makeIncompleteDraft(
        conversation: Conversation,
        content: String = "",
        thinking: String? = nil,
        responseId: String,
        lastSequenceNumber: Int,
        usedBackgroundMode: Bool
    ) -> Message {
        Message(
            role: .assistant,
            content: content,
            thinking: thinking,
            conversation: conversation,
            responseId: responseId,
            lastSequenceNumber: lastSequenceNumber,
            usedBackgroundMode: usedBackgroundMode,
            isComplete: false
        )
    }

    func assertRecoveredMessage(
        in store: ChatController,
        content: String,
        thinking: String
    ) throws {
        let recovered = try #require(latestAssistantMessage(in: store))
        #expect(recovered.content == content)
        #expect(recovered.thinking == thinking)
        #expect(recovered.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isRecovering)
    }
}
