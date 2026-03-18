import ChatApplication
import XCTest
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatUIComponents
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import ChatDomain
import ChatRuntimeModel
@testable import NativeChatComposition

@MainActor
final class ChatScreenStoreRuntimeTests: XCTestCase {
    func testSendMessageWithoutStoredAPIKeyFailsFastAndLeavesFreshInstallStateUsable() async throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let store = try makeTestChatScreenStore(apiKey: "", streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Missing Key")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        XCTAssertFalse(store.sendMessage(text: "This should not start"))
        XCTAssertEqual(store.errorMessage, "Please add your OpenAI API key in Settings.")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.currentVisibleSession)
        XCTAssertFalse(store.isStreaming)
        XCTAssertFalse(store.isThinking)
        XCTAssertTrue(streamClient.recordedRequests.isEmpty)
    }

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

        let activeReplyID = AssistantReplyID(rawValue: sessionMessageID(for: store))
        let runtimeSession = await store.runtimeRegistry.session(for: activeReplyID)
        let runtimeSnapshotValue = await runtimeSession?.snapshot()
        let runtimeSnapshot = try XCTUnwrap(runtimeSnapshotValue)
        XCTAssertEqual(runtimeSnapshot.buffer.text, "Partial answer")
        guard case .streaming(let cursor) = runtimeSnapshot.lifecycle else {
            return XCTFail("Expected runtime registry to track an active streaming reply")
        }
        XCTAssertEqual(cursor.responseID, "resp_stop_1")

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
        var runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
        if runtimeSessionStillRegistered {
            for _ in 0..<10 where runtimeSessionStillRegistered {
                try await Task.sleep(nanoseconds: 20_000_000)
                runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
            }
        }
        XCTAssertFalse(runtimeSessionStillRegistered)
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

    func testStartNewChatCancelsTrackedGeneratedFilePrefetch() async throws {
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

    func testHandleDidEnterBackgroundDoesNotInterruptActiveSessionImmediately() async throws {
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

        let cancelCallsBeforeBackground = streamClient.cancelCallCount
        store.handleDidEnterBackground()

        XCTAssertNotNil(store.currentVisibleSession)
        XCTAssertFalse(latestAssistantMessage(in: store)?.isComplete ?? true)
        XCTAssertEqual(streamClient.cancelCallCount, cancelCallsBeforeBackground)

        streamClient.yield(.responseCreated("resp_background_live"))
        streamClient.yield(.sequenceUpdate(3))
        streamClient.yield(.textDelta("Background completion"))
        streamClient.yield(.completed("", nil, nil))

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.isComplete == true && store.currentVisibleSession == nil
        }

        let assistantMessage = try XCTUnwrap(latestAssistantMessage(in: store))
        XCTAssertEqual(assistantMessage.content, "Background completion")
        XCTAssertEqual(assistantMessage.responseId, "resp_background_live")
        XCTAssertNil(assistantMessage.lastSequenceNumber)
        XCTAssertTrue(assistantMessage.isComplete)
        XCTAssertFalse(assistantMessage.content.contains("Response interrupted because the app was closed before completion."))
        XCTAssertFalse(store.isStreaming)
    }

    func testRelaunchedStoreFetchesCompletedResponseDirectlyAfterBackgroundDetachment() async throws {
        let container = try makeInMemoryModelContainer()
        let settingsValueStore = InMemorySettingsValueStore()
        settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

        let apiBackend = InMemoryAPIKeyBackend()
        apiBackend.storedKey = "sk-test"
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(
            container: container,
            settingsValueStore: settingsValueStore,
            apiBackend: apiBackend,
            configurationProvider: configurationProvider,
            transport: StubOpenAITransport(),
            streamClient: initialStreamClient,
            bootstrapPolicy: .testing
        )
        let conversation = try seedConversation(
            in: initialStore,
            title: "Completed After Relaunch",
            backgroundModeEnabled: false
        )

        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = false
        initialStore.syncConversationProjection()

        XCTAssertTrue(initialStore.sendMessage(text: "Fetch the completed result"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_relaunch_completed"))
        initialStreamClient.yield(.textDelta("Partial"))

        try await waitUntil {
            self.latestAssistantMessage(in: initialStore)?.responseId == "resp_relaunch_completed"
        }

        initialStore.handleEnterBackground()
        initialStore.suspendActiveSessionsForAppBackground()

        let suspendedMessage = try XCTUnwrap(latestAssistantMessage(in: initialStore))
        XCTAssertEqual(suspendedMessage.responseId, "resp_relaunch_completed")
        XCTAssertFalse(suspendedMessage.isComplete)

        let relaunchTransport = StubOpenAITransport()
        await relaunchTransport.enqueue(
            data: try makeFetchResponseData(
                status: .completed,
                text: "Fetched after relaunch",
                thinking: "Server-side completion"
            ),
            url: URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_completed")!
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let relaunchStore = makeRelaunchableStore(
            container: container,
            settingsValueStore: settingsValueStore,
            apiBackend: apiBackend,
            configurationProvider: configurationProvider,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            bootstrapPolicy: .init(
                restoreLastConversation: true,
                setupLifecycleObservers: false,
                runLaunchTasks: true
            )
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        let recovered = try XCTUnwrap(latestAssistantMessage(in: relaunchStore))
        XCTAssertEqual(recovered.content, "Fetched after relaunch")
        XCTAssertEqual(recovered.thinking, "Server-side completion")
        XCTAssertTrue(recovered.isComplete)
        XCTAssertNil(relaunchStore.currentVisibleSession)
        XCTAssertFalse(relaunchStore.isRecovering)
        let requestedPaths = await relaunchTransport.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/v1/responses/resp_relaunch_completed"])
        XCTAssertTrue(relaunchStreamClient.recordedRequests.isEmpty)
    }

    func testRelaunchedBackgroundModeSessionResumesStreamingWhenResponseStillInProgress() async throws {
        let container = try makeInMemoryModelContainer()
        let settingsValueStore = InMemorySettingsValueStore()
        settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

        let apiBackend = InMemoryAPIKeyBackend()
        apiBackend.storedKey = "sk-test"
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(
            container: container,
            settingsValueStore: settingsValueStore,
            apiBackend: apiBackend,
            configurationProvider: configurationProvider,
            transport: StubOpenAITransport(),
            streamClient: initialStreamClient,
            bootstrapPolicy: .testing
        )
        let conversation = try seedConversation(
            in: initialStore,
            title: "Resume After Relaunch",
            backgroundModeEnabled: true
        )

        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = true
        initialStore.syncConversationProjection()

        XCTAssertTrue(initialStore.sendMessage(text: "Resume the stream"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_relaunch_stream"))
        initialStreamClient.yield(.sequenceUpdate(7))
        initialStreamClient.yield(.textDelta("Partial "))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == "resp_relaunch_stream" && message?.lastSequenceNumber == 7
        }

        initialStore.handleEnterBackground()
        initialStore.suspendActiveSessionsForAppBackground()

        let suspendedMessage = try XCTUnwrap(latestAssistantMessage(in: initialStore))
        XCTAssertEqual(suspendedMessage.responseId, "resp_relaunch_stream")
        XCTAssertEqual(suspendedMessage.lastSequenceNumber, 7)
        XCTAssertFalse(suspendedMessage.isComplete)

        let relaunchTransport = StubOpenAITransport()
        await relaunchTransport.enqueue(
            data: try makeFetchResponseData(status: .inProgress, text: ""),
            url: URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_stream")!
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("continued"),
                .completed("Partial continued", "Recovered thinking", nil)
            ]]
        )
        let relaunchStore = makeRelaunchableStore(
            container: container,
            settingsValueStore: settingsValueStore,
            apiBackend: apiBackend,
            configurationProvider: configurationProvider,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            bootstrapPolicy: .init(
                restoreLastConversation: true,
                setupLifecycleObservers: false,
                runLaunchTasks: true
            )
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        let recovered = try XCTUnwrap(latestAssistantMessage(in: relaunchStore))
        XCTAssertEqual(recovered.content, "Partial continued")
        XCTAssertEqual(recovered.thinking, "Recovered thinking")
        XCTAssertTrue(recovered.isComplete)
        XCTAssertNil(recovered.lastSequenceNumber)
        XCTAssertNil(relaunchStore.currentVisibleSession)
        XCTAssertFalse(relaunchStore.isRecovering)
        let requestedPaths = await relaunchTransport.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/v1/responses/resp_relaunch_stream"])
        XCTAssertEqual(relaunchStreamClient.recordedRequests.count, 1)
        let resumeURL = try XCTUnwrap(relaunchStreamClient.recordedRequests.first?.url?.absoluteString)
        XCTAssertTrue(resumeURL.contains("starting_after=7"))
    }

    private func seedConversation(
        in store: ChatController,
        title: String,
        backgroundModeEnabled: Bool = false
    ) throws -> Conversation {
        let conversation = Conversation(
            title: title,
            model: ModelType.gpt5_4.rawValue,
            reasoningEffort: ReasoningEffort.high.rawValue,
            backgroundModeEnabled: backgroundModeEnabled,
            serviceTierRawValue: ServiceTier.standard.rawValue
        )
        store.modelContext.insert(conversation)
        try store.modelContext.save()
        return conversation
    }

    private func latestAssistantMessage(in store: ChatController) -> Message? {
        store.messages
            .filter { $0.role == .assistant }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    private func makeRelaunchableStore(
        container: ModelContainer,
        settingsValueStore: InMemorySettingsValueStore,
        apiBackend: InMemoryAPIKeyBackend,
        configurationProvider: RuntimeTestOpenAIConfigurationProvider,
        transport: OpenAIDataTransport,
        streamClient: OpenAIStreamClient,
        bootstrapPolicy: FeatureBootstrapPolicy
    ) -> ChatController {
        let context = ModelContext(container)
        let settingsStore = SettingsStore(valueStore: settingsValueStore)
        let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
        let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
        let responseParser = OpenAIResponseParser()
        let service = OpenAIService(
            requestBuilder: requestBuilder,
            responseParser: responseParser,
            streamClient: streamClient,
            transport: transport
        )

        return ChatController(
            modelContext: context,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            transport: transport,
            serviceFactory: { service },
            bootstrapPolicy: bootstrapPolicy
        )
    }

    private func sessionMessageID(for store: ChatController) -> UUID {
        if let session = store.currentVisibleSession {
            return session.messageID
        }
        if let draft = store.draftMessage {
            return draft.id
        }
        XCTFail("Expected an active visible session")
        return UUID()
    }
}

private actor SlowGeneratedFileDownloadTransport: OpenAIDataTransport {
    private var requestsSeen = 0
    private var cancellationsSeen = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestsSeen += 1
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.test.openai.local/v1/files/file_prefetch/content")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("%PDF".utf8), response)
        } catch {
            if Task.isCancelled {
                cancellationsSeen += 1
            }
            throw error
        }
    }

    func requestCount() -> Int {
        requestsSeen
    }

    func cancellationCount() -> Int {
        cancellationsSeen
    }
}
