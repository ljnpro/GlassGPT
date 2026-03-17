import Foundation
import SwiftUI

enum CloudflareHealthStatus: Equatable {
    case unknown
    case checking
    case connected
    case error(String)
}

@Observable
@MainActor
final class SettingsScreenStore {
    // MARK: - State

    var apiKey: String = ""
    var isAPIKeyValid: Bool?
    var isValidating: Bool = false
    var saveConfirmation: Bool = false

    var cloudflareHealthStatus: CloudflareHealthStatus = .unknown
    var isCheckingCloudflareHealth: Bool = false
    var generatedImageCacheSizeBytes: Int64 = 0
    var generatedDocumentCacheSizeBytes: Int64 = 0
    var isClearingImageCache: Bool = false
    var isClearingDocumentCache: Bool = false

    // MARK: - Persisted Settings (stored properties for @Observable tracking)

    private var defaultModel: ModelType {
        didSet {
            settingsStore.defaultModel = defaultModel
            if !defaultModel.availableEfforts.contains(defaultEffort) {
                defaultEffort = defaultModel.defaultEffort
            }
        }
    }

    var defaultProModeEnabled: Bool {
        get { defaultModel == .gpt5_4_pro }
        set { defaultModel = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    var defaultEffort: ReasoningEffort {
        didSet {
            settingsStore.defaultEffort = defaultEffort
        }
    }

    var defaultBackgroundModeEnabled: Bool {
        didSet {
            settingsStore.defaultBackgroundModeEnabled = defaultBackgroundModeEnabled
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            settingsStore.defaultServiceTier = defaultServiceTier
        }
    }

    var defaultFlexModeEnabled: Bool {
        get { defaultServiceTier == .flex }
        set { defaultServiceTier = newValue ? .flex : .standard }
    }

    var appTheme: AppTheme {
        didSet {
            settingsStore.appTheme = appTheme
        }
    }

    var hapticEnabled: Bool {
        didSet {
            settingsStore.hapticEnabled = hapticEnabled
        }
    }

    var cloudflareEnabled: Bool {
        didSet {
            guard cloudflareEnabled != oldValue else { return }
            dependencies.setCloudflareGatewayEnabled(cloudflareEnabled)
            if !cloudflareEnabled {
                cloudflareHealthStatus = .unknown
                isCheckingCloudflareHealth = false
            }
        }
    }

    // MARK: - Available efforts for current default model

    var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    var generatedImageCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedImageCacheSizeBytes)
    }

    var generatedImageCacheLimitString: String {
        Self.byteCountFormatter.string(fromByteCount: FileDownloadService.generatedImageCacheLimitBytes)
    }

    var generatedDocumentCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedDocumentCacheSizeBytes)
    }

    var generatedDocumentCacheLimitString: String {
        Self.byteCountFormatter.string(fromByteCount: FileDownloadService.generatedDocumentCacheLimitBytes)
    }

    // MARK: - Dependencies

    @ObservationIgnored
    let dependencies: NativeChatSettingsDependencies

    // MARK: - Init

    init(
        settingsStore: SettingsStore = .shared,
        apiKeyStore: APIKeyStore = .shared,
        openAIService: OpenAIService? = nil,
        requestBuilder: OpenAIRequestBuilder? = nil,
        transport: OpenAIDataTransport = OpenAIURLSessionTransport(),
        configurationProvider: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared
    ) {
        let resolvedRequestBuilder = requestBuilder ?? OpenAIRequestBuilder(configuration: configurationProvider)
        let resolvedOpenAIService = openAIService ?? OpenAIService(
            requestBuilder: resolvedRequestBuilder,
            streamClient: SSEEventStream(),
            transport: transport
        )
        self.dependencies = NativeChatSettingsDependencies(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            configurationProvider: configurationProvider,
            requestBuilder: resolvedRequestBuilder,
            responseParser: resolvedOpenAIService.responseParser,
            transport: transport,
            openAIService: resolvedOpenAIService
        )
        self.defaultModel = settingsStore.defaultModel
        self.defaultEffort = settingsStore.defaultEffort
        self.defaultBackgroundModeEnabled = settingsStore.defaultBackgroundModeEnabled
        self.defaultServiceTier = settingsStore.defaultServiceTier
        self.appTheme = settingsStore.appTheme
        self.hapticEnabled = settingsStore.hapticEnabled
        self.cloudflareEnabled = settingsStore.cloudflareGatewayEnabled
        self.apiKey = apiKeyStore.loadAPIKey() ?? ""

        if self.cloudflareEnabled {
            Task {
                await self.checkCloudflareHealth()
            }
        }

        Task {
            await self.refreshGeneratedImageCacheSize()
            await self.refreshGeneratedDocumentCacheSize()
        }
    }

}
