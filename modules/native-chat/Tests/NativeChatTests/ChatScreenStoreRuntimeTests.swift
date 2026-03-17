import XCTest
@testable import NativeChat

@MainActor
final class ChatScreenStoreRuntimeTests: XCTestCase {
    func testSendMessageStreamsThroughStoreAndFinalizesAssistantDraft() async throws {
        let streamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .responseCreated("resp_stream_1"),
                .thinkingStarted,
                .thinkingDelta("Plan the answer"),
                .webSearchStarted("ws_1"),
                .webSearchSearching("ws_1"),
                .webSearchCompleted("ws_1"),
                .annotationAdded(
                    URLCitation(
                        url: "https://example.com/plan",
                        title: "Plan",
                        startIndex: 0,
                        endIndex: 4
                    )
                ),
                .textDelta("Hello"),
                .textDelta(" world"),
                .completed("", "Plan the answer", nil)
            ]]
        )
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Runtime Tests")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        XCTAssertTrue(store.sendMessage(text: "Ship the refactor"))

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        let userMessage = try XCTUnwrap(store.messages.first(where: { $0.role == .user }))
        let assistantMessage = try XCTUnwrap(latestAssistantMessage(in: store))

        XCTAssertEqual(userMessage.content, "Ship the refactor")
        XCTAssertEqual(assistantMessage.content, "Hello world")
        XCTAssertEqual(assistantMessage.thinking, "Plan the answer")
        XCTAssertEqual(assistantMessage.responseId, "resp_stream_1")
        XCTAssertTrue(assistantMessage.isComplete)
        XCTAssertEqual(assistantMessage.annotations.count, 1)
        XCTAssertEqual(assistantMessage.toolCalls.count, 1)
        XCTAssertEqual(assistantMessage.toolCalls.first?.type, .webSearch)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertEqual(store.currentStreamingText, "")
        XCTAssertEqual(store.currentThinkingText, "")
        XCTAssertFalse(store.isStreaming)
        XCTAssertFalse(store.isThinking)
    }

    func testStopGenerationFinalizesVisibleDraftThroughStoreAPI() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Stop Generation")
        store.currentConversation = conversation
        store.syncConversationProjection()

        XCTAssertTrue(store.sendMessage(text: "Stop after partial"))

        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated("resp_stop_1"))
        streamClient.yield(.textDelta("Partial answer"))

        try await waitUntil {
            store.currentStreamingText == "Partial answer"
        }

        store.stopGeneration(savePartial: true)

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true
        }

        let assistantMessage = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertEqual(assistantMessage.content, "Partial answer")
        XCTAssertEqual(assistantMessage.responseId, "resp_stop_1")
        XCTAssertTrue(assistantMessage.isComplete)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertFalse(store.isStreaming)
        XCTAssertGreaterThanOrEqual(streamClient.cancelCallCount, 1)
    }

    func testRecoverResponseVisibleSessionResumesStreamingAndFinalizesThroughStoreAPI() async throws {
        let streamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("Recovered via stream"),
                .completed("", "Recovered reasoning", nil)
            ]]
        )
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: try makeFetchResponseData(status: .inProgress, text: ""),
            url: URL(string: "https://api.test.openai.local/v1/responses/resp_stream_resume")!
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Manual Recovery")
        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            responseId: "resp_stream_resume",
            lastSequenceNumber: 7,
            usedBackgroundMode: true,
            isComplete: false
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

        let recovered = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertEqual(recovered.content, "Recovered via stream")
        XCTAssertEqual(recovered.thinking, "Recovered reasoning")
        XCTAssertNil(recovered.lastSequenceNumber)
        XCTAssertTrue(recovered.isComplete)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertFalse(store.isRecovering)
        let requestedPaths = await transport.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/v1/responses/resp_stream_resume"])
        XCTAssertEqual(streamClient.recordedRequests.count, 1)
    }

    func testRecoverResponse404UsesFallbackAndClearsVisibleRuntimeState() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: Data("gone".utf8),
            statusCode: 404,
            url: URL(string: "https://api.test.openai.local/v1/responses/resp_missing")!
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "404 Recovery")
        let draft = Message(
            role: .assistant,
            content: "Partial response",
            thinking: "Keep this reasoning",
            conversation: conversation,
            responseId: "resp_missing",
            lastSequenceNumber: 5,
            usedBackgroundMode: true,
            isComplete: false
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

        let recovered = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertEqual(recovered.content, "Partial response")
        XCTAssertEqual(recovered.thinking, "Keep this reasoning")
        XCTAssertTrue(recovered.isComplete)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertFalse(store.isRecovering)
        let requestedPaths = await transport.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/v1/responses/resp_missing"])
    }

    func testRecoverResponseInvisiblePollingFinalizesMessageWithoutBindingVisibleSession() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let transport = StubOpenAITransport()
        await transport.enqueue(
            data: try makeFetchResponseData(
                status: .completed,
                text: "Recovered via polling",
                thinking: "Recovered hidden reasoning"
            ),
            url: URL(string: "https://api.test.openai.local/v1/responses/resp_hidden_resume")!
        )

        let store = try makeTestChatScreenStore(transport: transport, streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Invisible Recovery")
        let draft = Message(
            role: .assistant,
            content: "",
            thinking: nil,
            conversation: conversation,
            responseId: "resp_hidden_resume",
            lastSequenceNumber: 2,
            usedBackgroundMode: false,
            isComplete: false
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

        let recovered = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertEqual(recovered.content, "Recovered via polling")
        XCTAssertEqual(recovered.thinking, "Recovered hidden reasoning")
        XCTAssertTrue(recovered.isComplete)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertFalse(store.isRecovering)
        let requestedPaths = await transport.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/v1/responses/resp_hidden_resume"])
        XCTAssertTrue(streamClient.recordedRequests.isEmpty)
    }

    func testHandleDidEnterBackgroundSuspendsActiveSessionAndPersistsInterruptionFallback() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Background Session")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        XCTAssertTrue(store.sendMessage(text: "Keep going"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.textDelta("Partial output"))

        try await waitUntil {
            store.currentStreamingText == "Partial output"
        }

        store.handleDidEnterBackground()

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true && store.currentVisibleSession == nil
        }

        let assistantMessage = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertTrue(assistantMessage.content.contains("Partial output"))
        XCTAssertTrue(assistantMessage.content.contains("Response interrupted because the app was closed before completion."))
        XCTAssertNil(assistantMessage.lastSequenceNumber)
        XCTAssertTrue(assistantMessage.isComplete)
        XCTAssertGreaterThanOrEqual(streamClient.cancelCallCount, 1)
        XCTAssertFalse(store.isStreaming)
    }

    private func seedConversation(in store: ChatScreenStore, title: String) throws -> Conversation {
        let conversation = Conversation(
            title: title,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: false,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        store.modelContext.insert(conversation)
        try store.modelContext.save()
        return conversation
    }

    private func latestAssistantMessage(in store: ChatScreenStore) -> Message? {
        store.messages
            .filter { $0.role == .assistant }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }
}
