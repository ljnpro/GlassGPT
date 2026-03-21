// swiftlint:disable file_length
import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import XCTest
@testable import NativeChatComposition

final class RuntimeTestOpenAIConfigurationProvider: OpenAIConfigurationProvider, @unchecked Sendable {
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

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        if let saveError {
            if let persistenceError = saveError as? PersistenceError {
                throw persistenceError
            }
            throw .keychainFailure(-1)
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

func makeTestAsyncStream<Element>() -> (
    stream: AsyncStream<Element>,
    continuation: AsyncStream<Element>.Continuation
) {
    var capturedContinuation: AsyncStream<Element>.Continuation?
    let stream = AsyncStream<Element> { continuation in
        capturedContinuation = continuation
    }
    // swiftlint:disable:next force_unwrapping
    return (stream, capturedContinuation!)
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
        // swiftlint:disable:next force_unwrapping
        url: URL = URL(string: "https://api.test.openai.local/v1/responses/test")!
    ) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
            // swiftlint:disable:next force_unwrapping
        )!
        queuedResponses.append(.success((data, response)))
    }

    func enqueue(error: Error) {
        queuedResponses.append(.failure(error))
    }

    func data(for request: URLRequest) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else {
            throw .requestFailed("Missing stubbed transport response")
        }
        do {
            return try queuedResponses.removeFirst().get()
        } catch {
            if let serviceError = error as? OpenAIServiceError {
                throw serviceError
            }
            throw .requestFailed(error.localizedDescription)
        }
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
    let store: SettingsPresenter
    let settingsValueStore: InMemorySettingsValueStore
    let apiKeyBackend: InMemoryAPIKeyBackend
    let cloudflareTokenBackend: InMemoryAPIKeyBackend
    let configurationProvider: RuntimeTestOpenAIConfigurationProvider
    let transport: OpenAIDataTransport
}

private func releaseVersionsConfigURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("ios/GlassGPT/Config/Versions.xcconfig")
}

private func releaseVersionsConfigValues() -> (marketing: String, build: String) {
    let configURL = releaseVersionsConfigURL()
    guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
        return ("Unknown", "?")
    }

    func value(for key: String) -> String? {
        text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, parts[0] == key else { return nil }
                return parts[1]
            }
            .first
    }

    return (
        value(for: "MARKETING_VERSION") ?? "Unknown",
        value(for: "CURRENT_PROJECT_VERSION") ?? "?"
    )
}

func currentReleaseVersionString() -> String {
    let values = releaseVersionsConfigValues()
    return "\(values.marketing) (\(values.build))"
}

@MainActor
func makeTestChatScreenStore(
    apiKey: String = "sk-test",
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport(),
    fileDownloadService: FileDownloadService? = nil,
    streamClient: OpenAIStreamClient,
    bootstrapPolicy: FeatureBootstrapPolicy = .testing
) throws -> ChatController {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    settingsValueStore.set(false, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)

    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = apiKey

    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let responseParser = OpenAIResponseParser()
    let sharedService = OpenAIService(
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
        fileDownloadService: fileDownloadService,
        serviceFactory: { sharedService },
        bootstrapPolicy: bootstrapPolicy
    )
}

@MainActor
func makeTestSettingsScreenStore(
    apiKey: String? = nil,
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsPresenter {
    makeTestSettingsScreenStoreHarness(
        apiKey: apiKey,
        configurationProvider: configurationProvider,
        transport: transport
    ).store
}

@MainActor
func makeTestSettingsPresenter(
    apiKey: String? = nil,
    configurationProvider: RuntimeTestOpenAIConfigurationProvider = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsPresenter {
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
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let cloudflareTokenBackend = InMemoryAPIKeyBackend()
    let cloudflareTokenStore = PersistedAPIKeyStore(backend: cloudflareTokenBackend)
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let openAIService = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: OpenAIResponseParser(),
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        transport: transport
    )
    let fileDownloadService = GeneratedFilesInfra.FileDownloadService(configurationProvider: configurationProvider)
    let defaultGatewayBaseURL = configurationProvider.cloudflareGatewayBaseURL
    let defaultGatewayToken = configurationProvider.cloudflareAIGToken

    return SettingsScreenStoreHarness(
        store: makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            cloudflareTokenStore: cloudflareTokenStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider,
            fileDownloadService: fileDownloadService,
            applyCloudflareConfiguration: {
                let persistedCustomBaseURL = settingsStore.customCloudflareGatewayBaseURL
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let persistedCustomToken = cloudflareTokenStore.loadAPIKey()?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                switch settingsStore.cloudflareGatewayConfigurationMode {
                case .default:
                    configurationProvider.cloudflareGatewayBaseURL = defaultGatewayBaseURL
                    configurationProvider.cloudflareAIGToken = defaultGatewayToken
                case .custom:
                    configurationProvider.cloudflareGatewayBaseURL = persistedCustomBaseURL.isEmpty
                        ? defaultGatewayBaseURL
                        : persistedCustomBaseURL
                    configurationProvider.cloudflareAIGToken = persistedCustomToken.isEmpty
                        ? defaultGatewayToken
                        : persistedCustomToken
                }

                configurationProvider.useCloudflareGateway = settingsStore.cloudflareGatewayEnabled
            },
            appVersionString: currentReleaseVersionString(),
            platformString: "iOS 26.0 · Liquid Glass"
        ),
        settingsValueStore: settingsValueStore,
        apiKeyBackend: apiBackend,
        cloudflareTokenBackend: cloudflareTokenBackend,
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

func waitUntilAsync(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 20_000_000,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }

    XCTFail("Timed out waiting for async condition", file: file, line: line)
    throw NativeChatTestError.timeout
}
