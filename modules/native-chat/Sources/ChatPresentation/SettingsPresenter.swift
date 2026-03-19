import ChatApplication
import ChatDomain
import Foundation
import Observation
import OSLog

/// Observable presenter that drives the settings view, managing API key validation,
/// cache sizes, and preference changes.
///
/// All properties and methods are `@MainActor`-isolated.
@Observable
@MainActor
public final class SettingsPresenter {
    /// The current API key text entered by the user.
    public var apiKey: String
    /// Result of the most recent API key validation, or `nil` if not yet validated.
    public var isAPIKeyValid: Bool?
    /// Whether an API key validation request is in flight.
    public var isValidating = false
    /// Whether a save confirmation should be shown in the UI.
    public var saveConfirmation = false

    /// Current Cloudflare gateway health status.
    public var cloudflareHealthStatus: CloudflareHealthStatus = .unknown
    /// Whether a Cloudflare health check is in progress.
    public var isCheckingCloudflareHealth = false
    /// Current size in bytes of the generated image cache.
    public var generatedImageCacheSizeBytes: Int64 = 0
    /// Current size in bytes of the generated document cache.
    public var generatedDocumentCacheSizeBytes: Int64 = 0
    /// Whether the image cache is currently being cleared.
    public var isClearingImageCache = false
    /// Whether the document cache is currently being cleared.
    public var isClearingDocumentCache = false

    private var defaultModel: ModelType {
        didSet {
            controller.persistDefaultModel(defaultModel)
            if !defaultModel.availableEfforts.contains(defaultEffort) {
                defaultEffort = defaultModel.defaultEffort
            }
        }
    }

    /// Whether Pro mode is enabled. Toggling this switches between `.gpt5_4_pro` and `.gpt5_4`.
    public var defaultProModeEnabled: Bool {
        get { defaultModel == .gpt5_4_pro }
        set { defaultModel = newValue ? .gpt5_4_pro : .gpt5_4 }
    }

    /// The user's selected default reasoning effort. Persisted on change.
    public var defaultEffort: ReasoningEffort {
        didSet {
            controller.persistDefaultEffort(defaultEffort)
        }
    }

    /// Whether background mode is enabled by default. Persisted on change.
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

    /// Whether flex (economy) mode is enabled. Toggling this switches between `.flex` and `.standard`.
    public var defaultFlexModeEnabled: Bool {
        get { defaultServiceTier == .flex }
        set { defaultServiceTier = newValue ? .flex : .standard }
    }

    /// The selected app theme. Persisted on change.
    public var appTheme: AppTheme {
        didSet {
            controller.persistAppTheme(appTheme)
        }
    }

    /// Whether haptic feedback is enabled. Persisted on change.
    public var hapticEnabled: Bool {
        didSet {
            controller.persistHapticEnabled(hapticEnabled)
        }
    }

    /// Whether the Cloudflare AI gateway is enabled. Persisted on change; updates health status.
    public var cloudflareEnabled: Bool {
        didSet {
            guard cloudflareEnabled != oldValue else { return }
            controller.persistCloudflareEnabled(cloudflareEnabled)
            if !cloudflareEnabled {
                cloudflareHealthStatus = .unknown
                isCheckingCloudflareHealth = false
            } else {
                cloudflareHealthStatus = controller.resolveCloudflareHealth(
                    typedAPIKey: apiKey,
                    gatewayEnabled: cloudflareEnabled
                )
            }
        }
    }

    /// The app version string displayed in the settings footer.
    public let appVersionString: String
    /// The platform string displayed in the settings footer (e.g. "iOS", "macOS").
    public let platformString: String

    /// The reasoning efforts available for the currently selected model.
    public var availableDefaultEfforts: [ReasoningEffort] {
        defaultModel.availableEfforts
    }

    /// Human-readable string for the current image cache size (e.g. "12.3 MB").
    public var generatedImageCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedImageCacheSizeBytes)
    }

    /// Human-readable string for the current document cache size.
    public var generatedDocumentCacheSizeString: String {
        Self.byteCountFormatter.string(fromByteCount: generatedDocumentCacheSizeBytes)
    }

    /// Human-readable string for the image cache size limit.
    public var generatedImageCacheLimitString: String
    /// Human-readable string for the document cache size limit.
    public var generatedDocumentCacheLimitString: String

    private static let logger = Logger(subsystem: "GlassGPT", category: "settings")
    private let controller: SettingsSceneController

    /// Creates a settings presenter with the given initial values and controller.
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
        self.cloudflareHealthStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: cloudflareEnabled
        )
    }

    /// Trims and saves the current API key, updating save confirmation and Cloudflare health.
    public func saveAPIKey() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try controller.saveAPIKey(trimmedKey)
            apiKey = trimmedKey
            saveConfirmation = true
            if cloudflareEnabled {
                cloudflareHealthStatus = controller.resolveCloudflareHealth(
                    typedAPIKey: apiKey,
                    gatewayEnabled: cloudflareEnabled
                )
            }
        } catch {
            Self.logger.error("Failed to save API key: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the API key and resets validation state.
    public func clearAPIKey() {
        apiKey = ""
        controller.clearAPIKey()
        isAPIKeyValid = nil
        if cloudflareEnabled {
            cloudflareHealthStatus = controller.resolveCloudflareHealth(
                typedAPIKey: apiKey,
                gatewayEnabled: cloudflareEnabled
            )
        }
    }

    /// Validates the current API key against the OpenAI API and updates ``isAPIKeyValid``.
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

    /// Performs a Cloudflare gateway health check and updates ``cloudflareHealthStatus``.
    public func checkCloudflareHealth() async {
        guard cloudflareEnabled else {
            cloudflareHealthStatus = .unknown
            isCheckingCloudflareHealth = false
            return
        }

        let localStatus = controller.resolveCloudflareHealth(
            typedAPIKey: apiKey,
            gatewayEnabled: cloudflareEnabled
        )
        guard localStatus == .unknown else {
            cloudflareHealthStatus = localStatus
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

    /// Refreshes the generated image cache size display.
    public func refreshGeneratedImageCacheSize() async {
        generatedImageCacheSizeBytes = await controller.refreshGeneratedImageCacheSize()
    }

    /// Refreshes the generated document cache size display.
    public func refreshGeneratedDocumentCacheSize() async {
        generatedDocumentCacheSizeBytes = await controller.refreshGeneratedDocumentCacheSize()
    }

    /// Clears the generated image cache and updates the displayed size.
    public func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }
        isClearingImageCache = true
        generatedImageCacheSizeBytes = await controller.clearGeneratedImageCache()
        isClearingImageCache = false
    }

    /// Clears the generated document cache and updates the displayed size.
    public func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }
        isClearingDocumentCache = true
        generatedDocumentCacheSizeBytes = await controller.clearGeneratedDocumentCache()
        isClearingDocumentCache = false
    }

    /// Shared formatter for converting byte counts to human-readable strings.
    public static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
