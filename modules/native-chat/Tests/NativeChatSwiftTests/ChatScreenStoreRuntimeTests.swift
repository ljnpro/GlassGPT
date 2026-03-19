import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

@Suite(.serialized)
@MainActor
struct ChatScreenStoreRuntimeTests {
    @Test func `send message without stored API key fails fast and leaves fresh install state usable`() throws {
        let streamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let store = try makeTestChatScreenStore(apiKey: "", streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Missing Key")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        #expect(!store.sendMessage(text: "This should not start"))
        #expect(store.errorMessage == "Please add your OpenAI API key in Settings.")
        #expect(store.messages.isEmpty)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isStreaming)
        #expect(!store.isThinking)
        #expect(streamClient.recordedRequests.isEmpty)
    }

    @Test func `send message streams through store and finalizes assistant draft`() async throws {
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

        #expect(store.sendMessage(text: "Ship the refactor"))

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true
        }

        let userMessage = try #require(store.messages.first(where: { $0.role == .user }))
        let assistantMessage = try #require(latestAssistantMessage(in: store))

        #expect(userMessage.content == "Ship the refactor")
        #expect(assistantMessage.content == "Hello world")
        #expect(assistantMessage.thinking == "Plan the answer")
        #expect(assistantMessage.responseId == "resp_stream_1")
        #expect(assistantMessage.isComplete)
        #expect(assistantMessage.annotations.count == 1)
        #expect(assistantMessage.toolCalls.count == 1)
        #expect(assistantMessage.toolCalls.first?.type == .webSearch)
        #expect(store.currentVisibleSession == nil)
        #expect(store.currentStreamingText == "")
        #expect(store.currentThinkingText == "")
        #expect(!store.isStreaming)
        #expect(!store.isThinking)
    }

    @Test func `stop generation finalizes visible draft through store API`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Stop Generation")
        store.currentConversation = conversation
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Stop after partial"))

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
        let runtimeSnapshot = try #require(runtimeSnapshotValue)
        #expect(runtimeSnapshot.buffer.text == "Partial answer")
        guard case let .streaming(cursor) = runtimeSnapshot.lifecycle else {
            Issue.record("Expected runtime registry to track an active streaming reply")
            return
        }
        #expect(cursor.responseID == "resp_stop_1")

        store.stopGeneration(savePartial: true)

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true
        }

        let assistantMessage = try #require(latestAssistantMessage(in: store))
        #expect(assistantMessage.content == "Partial answer")
        #expect(assistantMessage.responseId == "resp_stop_1")
        #expect(assistantMessage.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isStreaming)
        #expect(streamClient.cancelCallCount >= 1)
        var runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
        if runtimeSessionStillRegistered {
            for _ in 0 ..< 10 where runtimeSessionStillRegistered {
                try await Task.sleep(nanoseconds: 20_000_000)
                runtimeSessionStillRegistered = await store.runtimeRegistry.contains(activeReplyID)
            }
        }
        #expect(!runtimeSessionStillRegistered)
    }

    @Test func `handle did enter background does not interrupt active session immediately`() async throws {
        let streamClient = ControlledOpenAIStreamClient()
        let store = try makeTestChatScreenStore(streamClient: streamClient)
        let conversation = try seedConversation(in: store, title: "Background Session")

        store.currentConversation = conversation
        store.messages = []
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Keep going"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        let cancelCallsBeforeBackground = streamClient.cancelCallCount
        store.handleDidEnterBackground()

        #expect(store.currentVisibleSession != nil)
        #expect(!(latestAssistantMessage(in: store)?.isComplete ?? true))
        #expect(streamClient.cancelCallCount == cancelCallsBeforeBackground)

        streamClient.yield(.responseCreated("resp_background_live"))
        streamClient.yield(.sequenceUpdate(3))
        streamClient.yield(.textDelta("Background completion"))
        streamClient.yield(.completed("", nil, nil))

        try await waitUntil {
            latestAssistantMessage(in: store)?.isComplete == true && store.currentVisibleSession == nil
        }

        let assistantMessage = try #require(latestAssistantMessage(in: store))
        #expect(assistantMessage.content == "Background completion")
        #expect(assistantMessage.responseId == "resp_background_live")
        #expect(assistantMessage.lastSequenceNumber == nil)
        #expect(assistantMessage.isComplete)
        #expect(!assistantMessage.content.contains("Response interrupted because the app was closed before completion."))
        #expect(!store.isStreaming)
    }
}

// MARK: - Private Helpers

extension ChatScreenStoreRuntimeTests {
    func seedConversation(
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

    func latestAssistantMessage(in store: ChatController) -> Message? {
        store.messages
            .filter { $0.role == .assistant }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    func makeRelaunchableStore(
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

    func sessionMessageID(for store: ChatController) -> UUID {
        if let session = store.currentVisibleSession {
            return session.messageID
        }
        if let draft = store.draftMessage {
            return draft.id
        }
        Issue.record("Expected an active visible session")
        return UUID()
    }
}

actor SlowGeneratedFileDownloadTransport: OpenAIDataTransport {
    private var requestsSeen = 0
    private var cancellationsSeen = 0

    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        requestsSeen += 1
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            let fallbackURL = try URL.requireValid("https://api.test.openai.local/v1/files/file_prefetch/content")
            let response = try HTTPURLResponse.require(
                url: request.url ?? fallbackURL,
                statusCode: 200
            )
            return (Data("%PDF".utf8), response)
        } catch is CancellationError {
            cancellationsSeen += 1
            throw .cancelled
        } catch {
            throw .requestFailed(error.localizedDescription)
        }
    }

    func requestCount() -> Int {
        requestsSeen
    }

    func cancellationCount() -> Int {
        cancellationsSeen
    }
}

private extension URL {
    static func requireValid(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw OpenAIServiceError.invalidURL
        }
        return url
    }
}

private extension HTTPURLResponse {
    static func require(url: URL, statusCode: Int) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw OpenAIServiceError.requestFailed("Failed to create HTTPURLResponse")
        }
        return response
    }
}
