import ChatApplication
import ChatDomain
import Foundation
import Observation

@Observable
@MainActor
public final class SettingsPresenter {
    public var apiKey: String
    public var isAPIKeyValid: Bool?
    public var isValidating = false
    public var saveConfirmation = false

    public var cloudflareHealthStatus: CloudflareHealthStatus = .unknown
    public var isCheckingCloudflareHealth = false
    public var generatedImageCacheSizeBytes: Int64 = 0
    public var generatedDocumentCacheSizeBytes: Int64 = 0
    public var isClearingImageCache = false
    public var isClearingDocumentCache = false

    private var defaultModel: ModelType {
        didSet {
            controller.persistDefaultModel(defaultModel)
            if !defaultModel.availableEfforts.contains(defaultEffort) {
                defaultEffort = defaultModel.defaultEffort
            }
        }
    }

    public var defaultProModeEnabled: Bool {
        get { defaultModel == .gpt5_4_pro }
        set { defaultModel = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    public var defaultEffort: ReasoningEffort {
        didSet {
            controller.persistDefaultEffort(defaultEffort)
        }
    }

    public var defaultBackgroundModeEnabled: Bool {
        didSet {
            controller.persistDefaultBackgroundModeEnabled(defaultBackgroundModeEnabled)
        }
    }

    private var defaultServiceTier: ServiceTier {
        didSet {
            controller.persistDefaultServiceTier(defaultServiceTier)
        }
    }

    public var defaultFlexModeEnabled: Bool {
        get { defaultServiceTier == .flex }
        set { defaultServiceTier = newValue ? .flex : .standard }
    }

    public var appTheme: AppTheme {
        didSet {
            controller.persistAppTheme(appTheme)
        }
    }

    public var hapticEnabled: Bool {
        didSet {
            controller.persistHapticEnabled(hapticEnabled)
        }
    }

    public var cloudflareEnabled: Bool {
        didSet {
            guard cloudflareEnabled != oldValue else { return }
            controller.persistCloudflareEnabled(cloudflareEnabled)
            if !cloudflareEnabled {
                cloudflareHealthStatus = .unknown
                isCheckingCloudflareHealth = false
            }
        }
    }

    public let appVersionString: String
    public let platformString: String

    public var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    public var generatedImageCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedImageCacheSizeBytes)
    }

    public var generatedDocumentCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedDocumentCacheSizeBytes)
    }

    public var generatedImageCacheLimitString: String
    public var generatedDocumentCacheLimitString: String

    private let controller: SettingsSceneController

    public init(
        apiKey: String,
        defaultModel: ModelType,
        defaultEffort: ReasoningEffort,
        defaultBackgroundModeEnabled: Bool,
        defaultServiceTier: ServiceTier,
        appTheme: AppTheme,
        hapticEnabled: Bool,
        cloudflareEnabled: Bool,
        appVersionString: String,
        platformString: String,
        generatedImageCacheLimitString: String,
        generatedDocumentCacheLimitString: String,
        controller: SettingsSceneController
    ) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.defaultEffort = defaultEffort
        self.defaultBackgroundModeEnabled = defaultBackgroundModeEnabled
        self.defaultServiceTier = defaultServiceTier
        self.appTheme = appTheme
        self.hapticEnabled = hapticEnabled
        self.cloudflareEnabled = cloudflareEnabled
        self.appVersionString = appVersionString
        self.platformString = platformString
        self.generatedImageCacheLimitString = generatedImageCacheLimitString
        self.generatedDocumentCacheLimitString = generatedDocumentCacheLimitString
        self.controller = controller
    }

    public func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try controller.saveAPIKey(trimmedKey)
            apiKey = trimmedKey
            saveConfirmation = true
        } catch {
        }
    }

    public func clearAPIKey() {
        apiKey = ""
        controller.clearAPIKey()
        isAPIKeyValid = nil
        if cloudflareEnabled {
            cloudflareHealthStatus = .unknown
        }
    }

    public func validateAPIKey() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            isAPIKeyValid = false
            return
        }

        isValidating = true
        isAPIKeyValid = await controller.validateAPIKey(trimmedKey)
        isValidating = false
    }

    public func checkCloudflareHealth() async {
        guard cloudflareEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        isCheckingCloudflareHealth = true
        cloudflareHealthStatus = .checking
        cloudflareHealthStatus = await controller.checkCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: cloudflareEnabled
        )
        isCheckingCloudflareHealth = false
    }

    public func refreshGeneratedImageCacheSize() async {
        generatedImageCacheSizeBytes = await controller.refreshGeneratedImageCacheSize()
    }

    public func refreshGeneratedDocumentCacheSize() async {
        generatedDocumentCacheSizeBytes = await controller.refreshGeneratedDocumentCacheSize()
    }

    public func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }
        isClearingImageCache = true
        generatedImageCacheSizeBytes = await controller.clearGeneratedImageCache()
        isClearingImageCache = false
    }

    public func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }
        isClearingDocumentCache = true
        generatedDocumentCacheSizeBytes = await controller.clearGeneratedDocumentCache()
        isClearingDocumentCache = false
    }

    public static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
