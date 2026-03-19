import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatPersistenceSwiftData
import GeneratedFilesInfra
import Foundation
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

@MainActor
func makeTestChatScreenStore(
    apiKey: String = "sk-test",
    configurationProvider: RuntimeTestOpenAIConfigurationProvider
        = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport(),
    fileDownloadService: FileDownloadService? = nil,
    streamClient: OpenAIStreamClient,
    bootstrapPolicy: FeatureBootstrapPolicy = .testing
) throws -> ChatController {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let settingsValueStore = InMemorySettingsValueStore()
    settingsValueStore.set(
        AppTheme.light.rawValue,
        forKey: SettingsStore.Keys.appTheme
    )
    settingsValueStore.set(
        false,
        forKey: SettingsStore.Keys.defaultBackgroundModeEnabled
    )
    settingsValueStore.set(
        false,
        forKey: SettingsStore.Keys.cloudflareGatewayEnabled
    )

    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = apiKey

    let settingsStore = SettingsStore(
        valueStore: settingsValueStore
    )
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let requestBuilder = OpenAIRequestBuilder(
        configuration: configurationProvider
    )
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
    configurationProvider: RuntimeTestOpenAIConfigurationProvider
        = RuntimeTestOpenAIConfigurationProvider(),
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
    configurationProvider: RuntimeTestOpenAIConfigurationProvider
        = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsPresenter {
    makeTestSettingsScreenStoreHarness(
        apiKey: apiKey,
        configurationProvider: configurationProvider,
        transport: transport
    ).store
}

@MainActor
private func makeDefaultSettingsValueStore(
    cloudflareEnabled: Bool
) -> InMemorySettingsValueStore {
    let store = InMemorySettingsValueStore()
    store.set(ModelType.gpt5_4_pro.rawValue, forKey: SettingsStore.Keys.defaultModel)
    store.set(ReasoningEffort.xhigh.rawValue, forKey: SettingsStore.Keys.defaultEffort)
    store.set(false, forKey: SettingsStore.Keys.defaultBackgroundModeEnabled)
    store.set(ServiceTier.standard.rawValue, forKey: SettingsStore.Keys.defaultServiceTier)
    store.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)
    store.set(true, forKey: SettingsStore.Keys.hapticEnabled)
    store.set(cloudflareEnabled, forKey: SettingsStore.Keys.cloudflareGatewayEnabled)
    return store
}

@MainActor
func makeTestSettingsScreenStoreHarness(
    apiKey: String? = nil,
    configurationProvider: RuntimeTestOpenAIConfigurationProvider
        = RuntimeTestOpenAIConfigurationProvider(),
    transport: OpenAIDataTransport = StubOpenAITransport()
) -> SettingsScreenStoreHarness {
    let settingsValueStore = makeDefaultSettingsValueStore(
        cloudflareEnabled: configurationProvider.useCloudflareGateway
    )
    let apiBackend = InMemoryAPIKeyBackend()
    apiBackend.storedKey = apiKey

    let settingsStore = SettingsStore(valueStore: settingsValueStore)
    let apiKeyStore = PersistedAPIKeyStore(backend: apiBackend)
    let requestBuilder = OpenAIRequestBuilder(configuration: configurationProvider)
    let openAIService = OpenAIService(
        requestBuilder: requestBuilder,
        responseParser: OpenAIResponseParser(),
        streamClient: QueuedOpenAIStreamClient(scriptedStreams: []),
        transport: transport
    )
    let fileDownloadService = GeneratedFilesInfra.FileDownloadService(
        configurationProvider: configurationProvider
    )

    return SettingsScreenStoreHarness(
        store: makeSettingsPresenter(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            openAIService: openAIService,
            requestBuilder: requestBuilder,
            transport: transport,
            configurationProvider: configurationProvider,
            fileDownloadService: fileDownloadService,
            appVersionString: currentReleaseVersionString(),
            platformString: "iOS 26.0 · Liquid Glass"
        ),
        settingsValueStore: settingsValueStore,
        apiKeyBackend: apiBackend,
        configurationProvider: configurationProvider,
        transport: transport
    )
}

private func makeMessageOutputItem(
    text: String,
    annotations: [ResponsesAnnotationDTO],
    filePathAnnotations: [ResponsesAnnotationDTO]
) -> ResponsesOutputItemDTO {
    let content = [ResponsesContentPartDTO(
        type: "output_text",
        text: text,
        annotations: annotations + filePathAnnotations
    )]
    return ResponsesOutputItemDTO(
        type: "message",
        id: nil,
        content: content,
        action: nil,
        query: nil,
        queries: nil,
        code: nil,
        results: nil,
        outputs: nil,
        text: nil,
        summary: nil
    )
}

private func makeReasoningOutputItem(
    thinking: String
) -> ResponsesOutputItemDTO {
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
        output.append(makeMessageOutputItem(
            text: text,
            annotations: annotations,
            filePathAnnotations: filePathAnnotations
        ))
    }
    if let thinking, !thinking.isEmpty {
        output.append(makeReasoningOutputItem(thinking: thinking))
    }
    output.append(contentsOf: toolCalls)
    let errorDTO = errorMessage.map { ResponsesErrorDTO(message: $0) }
    return try JSONCoding.encode(ResponsesResponseDTO(
        id: "resp_test",
        status: status.rawValue,
        output: output,
        error: errorDTO
    ))
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 20_000_000,
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

    Issue.record("Timed out waiting for condition")
    throw NativeChatTestError.timeout
}

func waitUntilAsync(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 20_000_000,
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }

    Issue.record("Timed out waiting for async condition")
    throw NativeChatTestError.timeout
}
