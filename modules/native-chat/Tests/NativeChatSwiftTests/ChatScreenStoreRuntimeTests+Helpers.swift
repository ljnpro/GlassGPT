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
        return ChatController(
            modelContext: context,
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            transport: transport,
            serviceFactory: {
                OpenAIService(
                    requestBuilder: requestBuilder,
                    responseParser: responseParser,
                    streamClient: streamClient,
                    transport: transport
                )
            },
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
