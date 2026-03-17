import Foundation
import SwiftData
import XCTest
@testable import NativeChat

final class RuntimeTestOpenAIConfigurationProvider: OpenAIConfigurationProvider {
    var directOpenAIBaseURL: String
    var cloudflareGatewayBaseURL: String
    var cloudflareAIGToken: String
    var useCloudflareGateway: Bool

    init(
        directOpenAIBaseURL: String = "https://api.test.openai.local/v1",
        cloudflareGatewayBaseURL: String = "https://gateway.test.openai.local/v1",
        cloudflareAIGToken: String = "cf-test-token",
        useCloudflareGateway: Bool = false
    ) {
        self.directOpenAIBaseURL = directOpenAIBaseURL
        self.cloudflareGatewayBaseURL = cloudflareGatewayBaseURL
        self.cloudflareAIGToken = cloudflareAIGToken
        self.useCloudflareGateway = useCloudflareGateway
    }

    var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
    }
}

final class InMemorySettingsValueStore: SettingsValueStore {
    var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

final class InMemoryAPIKeyBackend: APIKeyPersisting, @unchecked Sendable {
    var storedKey: String?
    var saveError: Error?
    var didDelete = false

    func saveAPIKey(_ apiKey: String) throws {
        if let saveError {
            throw saveError
        }
        storedKey = apiKey
    }

    func loadAPIKey() -> String? {
        storedKey
    }

    func deleteAPIKey() {
        didDelete = true
        storedKey = nil
    }
}

enum NativeChatTestError: Error {
    case saveFailed
    case missingStubbedTransportResponse
    case timeout
}

@MainActor
func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Conversation.self,
        Message.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

@MainActor
final class QueuedOpenAIStreamClient: OpenAIStreamClient {
    private(set) var recordedRequests: [URLRequest] = []
    private(set) var cancelCallCount = 0
    private var scriptedStreams: [[StreamEvent]]

    init(scriptedStreams: [[StreamEvent]]) {
        self.scriptedStreams = scriptedStreams
    }

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        recordedRequests.append(request)
        let events = scriptedStreams.isEmpty ? [] : scriptedStreams.removeFirst()
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func cancel() {
        cancelCallCount += 1
    }
}

@MainActor
final class ControlledOpenAIStreamClient: OpenAIStreamClient {
    private(set) var recordedRequests: [URLRequest] = []
    private(set) var cancelCallCount = 0
    private var continuations: [AsyncStream<StreamEvent>.Continuation] = []

    var activeStreamCount: Int {
        continuations.count
    }

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        recordedRequests.append(request)
        return AsyncStream { continuation in
            self.continuations.append(continuation)
        }
    }

    func cancel() {
        cancelCallCount += 1
        finishAll()
    }

    func yield(_ event: StreamEvent, onStreamAt index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].yield(event)
    }

    func finishStream(at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].finish()
    }

    func finishAll() {
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

actor StubOpenAITransport: OpenAIDataTransport {
    private var queuedResponses: [Result<(Data, URLResponse), Error>] = []
    private(set) var recordedRequests: [URLRequest] = []

    func enqueue(
        data: Data,
        statusCode: Int = 200,
        url: URL = URL(string: "https://api.test.openai.local/v1/responses/test")!
    ) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        queuedResponses.append(.success((data, response)))
    }

    func enqueue(error: Error) {
        queuedResponses.append(.failure(error))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else {
            throw NativeChatTestError.missingStubbedTransportResponse
        }
        return try queuedResponses.removeFirst().get()
    }

    func requestedPaths() -> [String] {
        recordedRequests.compactMap { $0.url?.path }
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

@MainActor
struct SettingsScreenStoreHarness {
    let store: SettingsScreenStore
    let settingsValueStore: InMemorySettingsValueStore
    let apiKeyBackend: InMemoryAPIKeyBackend
    let configurationProvider: RuntimeTestOpenAIConfigurationProvider
    let transport: OpenAIDataTransport
}

@MainActor
func makeTestChatScreenStore(
    apiKey: String = "sk-test",
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport(),
    streamClient: OpenAIStreamClient,
    bootstrapPolicy: ChatScreenStoreBootstrapPolicy = .testing
) throws -> ChatScreenStore {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = apiKey

    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = APIKeyStore(backend: apiBackend)
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let responseParser = OpenAIResponseParser()
    let sharedService = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: responseParser,
        streamClient: streamClient,
        transport: transport
    )

    return ChatScreenStore(
        modelContext: context,
        settingsStore: settingsStore,
        apiKeyStore: apiKeyStore,
        configurationProvider: configurationProvider,
        transport: transport,
        serviceFactory: { sharedService },
        bootstrapPolicy: bootstrapPolicy
    )
}

@MainActor
func makeTestSettingsScreenStore(
    apiKey: String? = nil,
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsScreenStore {
    makeTestSettingsScreenStoreHarness(
        apiKey: apiKey,
        configurationProvider: configurationProvider,
        transport: transport
    ).store
}

@MainActor
func makeTestSettingsScreenStoreHarness(
    apiKey: String? = nil,
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsScreenStoreHarness {
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(ModelType.gpt5_4_pro.rawValue, forKey: SettingsStore.Keys.defaultModel)
    settingsValueStore.set(ReasoningEffort.xhigh.rawValue, forKey: SettingsStore.Keys.defaultEffort)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(ServiceTier.standard.rawValue, forKey: SettingsStore.Keys.defaultServiceTier)
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(true, forKey: SettingsStore.Keys.hapticEnabled)
    settingsValueStore.set(configurationProvider.useCloudflareGateway, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = apiKey

    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = APIKeyStore(backend: apiBackend)
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let openAIService = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: OpenAIResponseParser(),
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        transport: transport
    )

    return SettingsScreenStoreHarness(
        store: SettingsScreenStore(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider
        ),
        settingsValueStore: settingsValueStore,
        apiKeyBackend: apiBackend,
        configurationProvider: configurationProvider,
        transport: transport
    )
}

func makeFetchResponseData(
    status: OpenAIResponseFetchResult.Status,
    text: String,
    thinking: String? = nil,
    annotations: [ResponsesAnnotationDTO] = [],
    toolCalls: [ResponsesOutputItemDTO] = [],
    filePathAnnotations: [ResponsesAnnotationDTO] = [],
    errorMessage: String? = nil
) throws -> Data {
    var output: [ResponsesOutputItemDTO] = []

    if !text.isEmpty || !annotations.isEmpty || !filePathAnnotations.isEmpty {
        output.append(
            ResponsesOutputItemDTO(
                type: "message",
                id: nil,
                content: [
                    ResponsesContentPartDTO(
                        type: "output_text",
                        text: text,
                        annotations: annotations + filePathAnnotations
                    )
                ],
                action: nil,
                query: nil,
                queries: nil,
                code: nil,
                results: nil,
                outputs: nil,
                text: nil,
                summary: nil
            )
        )
    }

    if let thinking, !thinking.isEmpty {
        output.append(
            ResponsesOutputItemDTO(
                type: "reasoning",
                id: nil,
                content: nil,
                action: nil,
                query: nil,
                queries: nil,
                code: nil,
                results: nil,
                outputs: nil,
                text: nil,
                summary: [ResponsesTextFragmentDTO(text: thinking)]
            )
        )
    }

    output.append(contentsOf: toolCalls)

    return try JSONCoding.encode(
        ResponsesResponseDTO(
            id: "resp_test",
            status: status.rawValue,
            output: output,
            error: errorMessage.map { ResponsesErrorDTO(message: $0) }
        )
    )
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 20_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
        await MainActor.run {}
    }

    XCTFail("Timed out waiting for condition", file: file, line: line)
    throw NativeChatTestError.timeout
}
