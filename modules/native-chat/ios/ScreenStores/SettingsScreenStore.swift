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
            configurationProvider.useCloudflareGateway = cloudflareEnabled
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

    private let apiKeyStore: APIKeyStore
    private let settingsStore: SettingsStore
    private let openAIService: OpenAIService
    private let requestBuilder: OpenAIRequestBuilder
    private nonisolated let transport: OpenAIDataTransport
    private var configurationProvider: OpenAIConfigurationProvider
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

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
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.configurationProvider = configurationProvider
        self.requestBuilder = resolvedRequestBuilder
        self.transport = transport
        self.openAIService = openAIService ?? OpenAIService(
            requestBuilder: resolvedRequestBuilder,
            streamClient: SSEEventStream(),
            transport: transport
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
                await checkCloudflareHealth()
            }
        }

        Task {
            await refreshGeneratedImageCacheSize()
            await refreshGeneratedDocumentCacheSize()
        }
    }

    // MARK: - Actions

    func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try apiKeyStore.saveAPIKey(trimmedKey)
            apiKey = trimmedKey
            saveConfirmation = true
            HapticService.shared.notify(.success)
        } catch {
            Loggers.settings.error("Failed to save API key: \(error.localizedDescription)")
        }
    }

    func clearAPIKey() {
        apiKey = ""
        apiKeyStore.deleteAPIKey()
        isAPIKeyValid = nil
        if cloudflareEnabled {
            cloudflareHealthStatus = .unknown
        }
        HapticService.shared.impact(.medium)
    }

    func validateAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            isAPIKeyValid = false
            return
        }

        isValidating = true
        isAPIKeyValid = await openAIService.validateAPIKey(trimmedKey)
        isValidating = false
        HapticService.shared.notify(isAPIKeyValid == true ? .success : .error)
    }

    func checkCloudflareHealth() async {
        guard cloudflareEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey: String
        if !typedKey.isEmpty {
            trimmedKey = typedKey
        } else {
            trimmedKey = apiKeyStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !trimmedKey.isEmpty else {
            cloudflareHealthStatus = .error("No API key configured")
            isCheckingCloudflareHealth = false
            return
        }

        let gatewayRequest: URLRequest
        do {
            gatewayRequest = try requestBuilder.modelsRequest(apiKey: trimmedKey)
        } catch {
            cloudflareHealthStatus = .error("Invalid gateway URL")
            isCheckingCloudflareHealth = false
            return
        }

        isCheckingCloudflareHealth = true
        cloudflareHealthStatus = .checking
        var request = gatewayRequest
        request.url = URL(string: "\(configurationProvider.cloudflareGatewayBaseURL)/models")

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                cloudflareHealthStatus = .error("Invalid gateway response")
                isCheckingCloudflareHealth = false
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                cloudflareHealthStatus = .connected
            } else {
                let message = Self.parseErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)"
                cloudflareHealthStatus = .error(message)
            }
        } catch {
            cloudflareHealthStatus = .error(error.localizedDescription)
        }

        isCheckingCloudflareHealth = false
    }

    func refreshGeneratedImageCacheSize() async {
        generatedImageCacheSizeBytes = await FileDownloadService.shared.generatedImageCacheSize()
    }

    func refreshGeneratedDocumentCacheSize() async {
        generatedDocumentCacheSizeBytes = await FileDownloadService.shared.generatedDocumentCacheSize()
    }

    func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }

        isClearingImageCache = true
        await FileDownloadService.shared.clearGeneratedImageCache()
        generatedImageCacheSizeBytes = await FileDownloadService.shared.generatedImageCacheSize()
        isClearingImageCache = false
        HapticService.shared.impact(.medium)
    }

    func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }

        isClearingDocumentCache = true
        await FileDownloadService.shared.clearGeneratedDocumentCache()
        generatedDocumentCacheSizeBytes = await FileDownloadService.shared.generatedDocumentCacheSize()
        isClearingDocumentCache = false
        HapticService.shared.impact(.medium)
    }

    // MARK: - Helpers

    private static func parseErrorMessage(from data: Data) -> String? {
        do {
            let payload = try JSONCoding.decode(SettingsErrorResponseDTO.self, from: data)
            if let message = payload.message, !message.isEmpty {
                return message
            }
            if let message = payload.error?.message, !message.isEmpty {
                return message
            }
        } catch {
            return String(data: data, encoding: .utf8)
        }

        return String(data: data, encoding: .utf8)
    }
}

private struct SettingsErrorResponseDTO: Decodable {
    let message: String?
    let error: ResponsesErrorDTO?
}
