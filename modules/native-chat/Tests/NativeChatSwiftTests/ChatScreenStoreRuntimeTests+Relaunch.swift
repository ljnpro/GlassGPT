import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

// MARK: - Relaunch Recovery Tests

extension ChatScreenStoreRuntimeTests {
    @Test func `relaunched store fetches completed response directly after background detachment`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        try await simulateInitialSession(
            store: initialStore,
            streamClient: initialStreamClient,
            title: "Completed After Relaunch",
            backgroundModeEnabled: false,
            responseId: "resp_relaunch_completed"
        )

        let relaunchTransport = StubOpenAITransport()
        let relaunchURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_completed")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(
                status: .completed,
                text: "Fetched after relaunch",
                thinking: "Server-side completion"
            ),
            url: relaunchURL
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(scriptedStreams: [])
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        try assertRelaunchedRecovery(
            in: relaunchStore,
            expectedContent: "Fetched after relaunch",
            expectedThinking: "Server-side completion"
        )
        let requestedPaths = await relaunchTransport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_relaunch_completed"])
        #expect(relaunchStreamClient.recordedRequests.isEmpty)
    }

    @Test func `relaunched background mode session resumes streaming when response still in progress`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        try await simulateInitialBackgroundSession(
            store: initialStore,
            streamClient: initialStreamClient,
            title: "Resume After Relaunch",
            responseId: "resp_relaunch_stream"
        )

        let relaunchTransport = StubOpenAITransport()
        let streamURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_relaunch_stream")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: streamURL
        )

        let relaunchStreamClient = QueuedOpenAIStreamClient(
            scriptedStreams: [[
                .sequenceUpdate(8),
                .textDelta("continued"),
                .completed("Partial continued", "Recovered thinking", nil)
            ]]
        )
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }

        try assertRelaunchedRecovery(
            in: relaunchStore,
            expectedContent: "Partial continued",
            expectedThinking: "Recovered thinking"
        )
        let recovered = try #require(latestAssistantMessage(in: relaunchStore))
        #expect(recovered.lastSequenceNumber == nil)
        let requestedPaths = await relaunchTransport.requestedPaths()
        #expect(requestedPaths == ["/v1/responses/resp_relaunch_stream"])
        #expect(relaunchStreamClient.recordedRequests.count == 1)
        let resumeURL = try #require(relaunchStreamClient.recordedRequests.first?.url?.absoluteString)
        #expect(resumeURL.contains("starting_after=7"))
    }

    @Test func `relaunched recovery hydrates persisted draft content before resumed events arrive`() async throws {
        let deps = try makeRelaunchDependencies()

        let initialStreamClient = ControlledOpenAIStreamClient()
        let initialStore = makeRelaunchableStore(deps: deps, streamClient: initialStreamClient)
        let conversation = try seedConversation(
            in: initialStore,
            title: "Hydrated Recovery",
            backgroundModeEnabled: true
        )

        initialStore.currentConversation = conversation
        initialStore.messages = []
        initialStore.backgroundModeEnabled = true
        initialStore.syncConversationProjection()

        #expect(initialStore.sendMessage(text: "Hydrate recovery state"))
        try await waitUntil {
            initialStore.currentVisibleSession != nil && initialStreamClient.activeStreamCount > 0
        }

        initialStreamClient.yield(.responseCreated("resp_hydrated_recovery"))
        initialStreamClient.yield(.sequenceUpdate(11))
        initialStreamClient.yield(.thinkingStarted)
        initialStreamClient.yield(.thinkingDelta("Persisted reasoning"))
        initialStreamClient.yield(.textDelta("Persisted answer"))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: initialStore)
            return message?.responseId == "resp_hydrated_recovery" &&
                message?.lastSequenceNumber == 11
        }

        initialStore.handleEnterBackground()
        await initialStore.suspendActiveSessionsForAppBackgroundNow()

        let relaunchTransport = StubOpenAITransport()
        let streamURL = try #require(
            URL(string: "https://api.test.openai.local/v1/responses/resp_hydrated_recovery")
        )
        try await relaunchTransport.enqueue(
            data: makeFetchResponseData(status: .inProgress, text: ""),
            url: streamURL
        )

        let relaunchStreamClient = ControlledOpenAIStreamClient()
        let relaunchStore = makeRelaunchableStore(
            deps: deps,
            transport: relaunchTransport,
            streamClient: relaunchStreamClient,
            restoreConversation: true
        )

        try await waitUntil {
            relaunchStore.currentVisibleSession != nil &&
                relaunchStore.isRecovering &&
                relaunchStore.currentStreamingText == "Persisted answer" &&
                relaunchStore.currentThinkingText == "Persisted reasoning" &&
                relaunchStore.isThinking
        }

        relaunchStreamClient.yield(.completed("Persisted answer", "Persisted reasoning", nil))

        try await waitUntil {
            self.latestAssistantMessage(in: relaunchStore)?.isComplete == true
        }
    }
}

// MARK: - Relaunch Test Helpers

extension ChatScreenStoreRuntimeTests {
    struct RelaunchDependencies {
        let container: ModelContainer
        let settingsValueStore: InMemorySettingsValueStore
        let apiBackend: InMemoryAPIKeyBackend
        let configurationProvider: RuntimeTestOpenAIConfigurationProvider
    }

    func makeRelaunchDependencies() throws -> RelaunchDependencies {
        let container = try makeInMemoryModelContainer()
        let settingsValueStore = InMemorySettingsValueStore()
        settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
        settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

        let apiBackend = InMemoryAPIKeyBackend()
        apiBackend.storedKey = "sk-test"
        let configurationProvider = RuntimeTestOpenAIConfigurationProvider()

        return RelaunchDependencies(
            container: container,
            settingsValueStore: settingsValueStore,
            apiBackend: apiBackend,
            configurationProvider: configurationProvider
        )
    }

    func makeRelaunchableStore(
        deps: RelaunchDependencies,
        transport: OpenAIDataTransport? = nil,
        streamClient: OpenAIStreamClient,
        restoreConversation: Bool = false
    ) -> ChatController {
        let resolvedTransport = transport ?? StubOpenAITransport()
        let policy: FeatureBootstrapPolicy = restoreConversation
            ? .init(restoreLastConversation: true, setupLifecycleObservers: false, runLaunchTasks: true)
            : .testing
        return makeRelaunchableStore(
            container: deps.container,
            settingsValueStore: deps.settingsValueStore,
            apiBackend: deps.apiBackend,
            configurationProvider: deps.configurationProvider,
            transport: resolvedTransport,
            streamClient: streamClient,
            bootstrapPolicy: policy
        )
    }

    func simulateInitialSession(
        store: ChatController,
        streamClient: ControlledOpenAIStreamClient,
        title: String,
        backgroundModeEnabled: Bool,
        responseId: String
    ) async throws {
        let conversation = try seedConversation(
            in: store, title: title, backgroundModeEnabled: backgroundModeEnabled
        )
        store.currentConversation = conversation
        store.messages = []
        store.backgroundModeEnabled = backgroundModeEnabled
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Fetch the completed result"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated(responseId))
        streamClient.yield(.textDelta("Partial"))

        try await waitUntil {
            self.latestAssistantMessage(in: store)?.responseId == responseId
        }

        store.handleEnterBackground()
        await store.suspendActiveSessionsForAppBackgroundNow()

        let suspendedMessage = try #require(latestAssistantMessage(in: store))
        #expect(suspendedMessage.responseId == responseId)
        #expect(!suspendedMessage.isComplete)
    }

    func simulateInitialBackgroundSession(
        store: ChatController,
        streamClient: ControlledOpenAIStreamClient,
        title: String,
        responseId: String
    ) async throws {
        let conversation = try seedConversation(
            in: store, title: title, backgroundModeEnabled: true
        )
        store.currentConversation = conversation
        store.messages = []
        store.backgroundModeEnabled = true
        store.syncConversationProjection()

        #expect(store.sendMessage(text: "Resume the stream"))
        try await waitUntil {
            store.currentVisibleSession != nil && streamClient.activeStreamCount > 0
        }

        streamClient.yield(.responseCreated(responseId))
        streamClient.yield(.sequenceUpdate(7))
        streamClient.yield(.textDelta("Partial "))

        try await waitUntil {
            let message = self.latestAssistantMessage(in: store)
            return message?.responseId == responseId && message?.lastSequenceNumber == 7
        }

        store.handleEnterBackground()
        await store.suspendActiveSessionsForAppBackgroundNow()

        let suspendedMessage = try #require(latestAssistantMessage(in: store))
        #expect(suspendedMessage.responseId == responseId)
        #expect(suspendedMessage.lastSequenceNumber == 7)
        #expect(!suspendedMessage.isComplete)
    }

    func assertRelaunchedRecovery(
        in store: ChatController,
        expectedContent: String,
        expectedThinking: String
    ) throws {
        let recovered = try #require(latestAssistantMessage(in: store))
        #expect(recovered.content == expectedContent)
        #expect(recovered.thinking == expectedThinking)
        #expect(recovered.isComplete)
        #expect(store.currentVisibleSession == nil)
        #expect(!store.isRecovering)
    }
}
