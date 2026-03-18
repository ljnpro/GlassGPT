import ChatDomain
import Foundation

public enum CloudflareHealthStatus: Equatable, Sendable {
    case unknown
    case checking
    case connected
    case gatewayUnavailable
    case missingAPIKey
    case invalidGatewayURL
    case remoteError(String)
}

@MainActor
public final class SettingsSceneController {
    private let loadAPIKeyHandler: () -> String?
    private let saveAPIKeyHandler: (String) throws -> Void
    private let clearAPIKeyHandler: () -> Void
    private let validateAPIKeyHandler: (String) async -> Bool
    private let resolveCloudflareHealthHandler: (_ typedAPIKey: String, _ gatewayEnabled: Bool) -> CloudflareHealthStatus
    private let checkCloudflareHealthHandler: (_ typedAPIKey: String, _ gatewayEnabled: Bool) async -> CloudflareHealthStatus
    private let refreshGeneratedImageCacheSizeHandler: () async -> Int64
    private let refreshGeneratedDocumentCacheSizeHandler: () async -> Int64
    private let clearGeneratedImageCacheHandler: () async -> Int64
    private let clearGeneratedDocumentCacheHandler: () async -> Int64
    private let persistDefaultModelHandler: (ModelType) -> Void
    private let persistDefaultEffortHandler: (ReasoningEffort) -> Void
    private let persistDefaultBackgroundModeHandler: (Bool) -> Void
    private let persistDefaultServiceTierHandler: (ServiceTier) -> Void
    private let persistAppThemeHandler: (AppTheme) -> Void
    private let persistHapticEnabledHandler: (Bool) -> Void
    private let persistCloudflareEnabledHandler: (Bool) -> Void

    public init(
        loadAPIKey: @escaping () -> String?,
        saveAPIKey: @escaping (String) throws -> Void,
        clearAPIKey: @escaping () -> Void,
        validateAPIKey: @escaping (String) async -> Bool,
        resolveCloudflareHealth: @escaping (_ typedAPIKey: String, _ gatewayEnabled: Bool) -> CloudflareHealthStatus,
        checkCloudflareHealth: @escaping (_ typedAPIKey: String, _ gatewayEnabled: Bool) async -> CloudflareHealthStatus,
        refreshGeneratedImageCacheSize: @escaping () async -> Int64,
        refreshGeneratedDocumentCacheSize: @escaping () async -> Int64,
        clearGeneratedImageCache: @escaping () async -> Int64,
        clearGeneratedDocumentCache: @escaping () async -> Int64,
        persistDefaultModel: @escaping (ModelType) -> Void,
        persistDefaultEffort: @escaping (ReasoningEffort) -> Void,
        persistDefaultBackgroundModeEnabled: @escaping (Bool) -> Void,
        persistDefaultServiceTier: @escaping (ServiceTier) -> Void,
        persistAppTheme: @escaping (AppTheme) -> Void,
        persistHapticEnabled: @escaping (Bool) -> Void,
        persistCloudflareEnabled: @escaping (Bool) -> Void
    ) {
        self.loadAPIKeyHandler = loadAPIKey
        self.saveAPIKeyHandler = saveAPIKey
        self.clearAPIKeyHandler = clearAPIKey
        self.validateAPIKeyHandler = validateAPIKey
        self.resolveCloudflareHealthHandler = resolveCloudflareHealth
        self.checkCloudflareHealthHandler = checkCloudflareHealth
        self.refreshGeneratedImageCacheSizeHandler = refreshGeneratedImageCacheSize
        self.refreshGeneratedDocumentCacheSizeHandler = refreshGeneratedDocumentCacheSize
        self.clearGeneratedImageCacheHandler = clearGeneratedImageCache
        self.clearGeneratedDocumentCacheHandler = clearGeneratedDocumentCache
        self.persistDefaultModelHandler = persistDefaultModel
        self.persistDefaultEffortHandler = persistDefaultEffort
        self.persistDefaultBackgroundModeHandler = persistDefaultBackgroundModeEnabled
        self.persistDefaultServiceTierHandler = persistDefaultServiceTier
        self.persistAppThemeHandler = persistAppTheme
        self.persistHapticEnabledHandler = persistHapticEnabled
        self.persistCloudflareEnabledHandler = persistCloudflareEnabled
    }

    public func loadAPIKey() -> String? {
        loadAPIKeyHandler()
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try saveAPIKeyHandler(apiKey)
    }

    public func clearAPIKey() {
        clearAPIKeyHandler()
    }

    public func validateAPIKey(_ apiKey: String) async -> Bool {
        await validateAPIKeyHandler(apiKey)
    }

    public func resolveCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) -> CloudflareHealthStatus {
        resolveCloudflareHealthHandler(typedAPIKey, gatewayEnabled)
    }

    public func checkCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) async -> CloudflareHealthStatus {
        await checkCloudflareHealthHandler(typedAPIKey, gatewayEnabled)
    }

    public func refreshGeneratedImageCacheSize() async -> Int64 {
        await refreshGeneratedImageCacheSizeHandler()
    }

    public func refreshGeneratedDocumentCacheSize() async -> Int64 {
        await refreshGeneratedDocumentCacheSizeHandler()
    }

    public func clearGeneratedImageCache() async -> Int64 {
        await clearGeneratedImageCacheHandler()
    }

    public func clearGeneratedDocumentCache() async -> Int64 {
        await clearGeneratedDocumentCacheHandler()
    }

    public func persistDefaultModel(_ model: ModelType) {
        persistDefaultModelHandler(model)
    }

    public func persistDefaultEffort(_ effort: ReasoningEffort) {
        persistDefaultEffortHandler(effort)
    }

    public func persistDefaultBackgroundModeEnabled(_ enabled: Bool) {
        persistDefaultBackgroundModeHandler(enabled)
    }

    public func persistDefaultServiceTier(_ serviceTier: ServiceTier) {
        persistDefaultServiceTierHandler(serviceTier)
    }

    public func persistAppTheme(_ theme: AppTheme) {
        persistAppThemeHandler(theme)
    }

    public func persistHapticEnabled(_ enabled: Bool) {
        persistHapticEnabledHandler(enabled)
    }

    public func persistCloudflareEnabled(_ enabled: Bool) {
        persistCloudflareEnabledHandler(enabled)
    }
}
