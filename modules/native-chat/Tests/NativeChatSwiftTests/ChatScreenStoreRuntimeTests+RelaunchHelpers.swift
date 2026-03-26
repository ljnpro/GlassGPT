import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

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
