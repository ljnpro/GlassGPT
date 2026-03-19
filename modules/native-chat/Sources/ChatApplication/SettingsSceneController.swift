import ChatDomain
import ChatPersistenceCore
import Foundation

/// Represents the current health status of the Cloudflare AI gateway.
public enum CloudflareHealthStatus: Equatable, Sendable {
    /// Health has not been checked yet.
    case unknown
    /// A health check is currently in progress.
    case checking
    /// The gateway is reachable and functioning.
    case connected
    /// The gateway endpoint is unreachable.
    case gatewayUnavailable
    /// No API key is configured, so the check cannot proceed.
    case missingAPIKey
    /// The configured gateway URL is malformed.
    case invalidGatewayURL
    /// The gateway returned an error with the given description.
    case remoteError(String)
}

/// Orchestrates settings scene operations by delegating to credential, cache, and persistence handlers.
///
/// All methods are `@MainActor`-isolated.
@MainActor
public final class SettingsSceneController {
    private let credentialHandler: any SettingsCredentialHandler
    private let cacheHandler: any SettingsCacheHandler
    private let persistenceHandler: any SettingsPersistenceHandler

    /// Creates a controller with the given handler implementations.
    package init(
        credentialHandler: any SettingsCredentialHandler,
        cacheHandler: any SettingsCacheHandler,
        persistenceHandler: any SettingsPersistenceHandler
    ) {
        self.credentialHandler = credentialHandler
        self.cacheHandler = cacheHandler
        self.persistenceHandler = persistenceHandler
    }

    /// Loads the stored API key.
    public func loadAPIKey() -> String? {
        credentialHandler.loadAPIKey()
    }

    /// Persists the given API key.
    public func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        try credentialHandler.saveAPIKey(apiKey)
    }

    /// Removes the stored API key.
    public func clearAPIKey() {
        credentialHandler.clearAPIKey()
    }

    /// Validates the API key against the OpenAI API.
    public func validateAPIKey(_ apiKey: String) async -> Bool {
        await credentialHandler.validateAPIKey(apiKey)
    }

    /// Synchronously resolves the Cloudflare gateway health from local state.
    public func resolveCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) -> CloudflareHealthStatus {
        credentialHandler.resolveCloudflareHealth(typedAPIKey: typedAPIKey, gatewayEnabled: gatewayEnabled)
    }

    /// Performs an async health check against the Cloudflare gateway.
    public func checkCloudflareHealth(typedAPIKey: String, gatewayEnabled: Bool) async -> CloudflareHealthStatus {
        await credentialHandler.checkCloudflareHealth(typedAPIKey: typedAPIKey, gatewayEnabled: gatewayEnabled)
    }

    /// Returns the current generated image cache size in bytes.
    public func refreshGeneratedImageCacheSize() async -> Int64 {
        await cacheHandler.refreshGeneratedImageCacheSize()
    }

    /// Returns the current generated document cache size in bytes.
    public func refreshGeneratedDocumentCacheSize() async -> Int64 {
        await cacheHandler.refreshGeneratedDocumentCacheSize()
    }

    /// Clears the generated image cache and returns the new size (should be zero).
    public func clearGeneratedImageCache() async -> Int64 {
        await cacheHandler.clearGeneratedImageCache()
    }

    /// Clears the generated document cache and returns the new size (should be zero).
    public func clearGeneratedDocumentCache() async -> Int64 {
        await cacheHandler.clearGeneratedDocumentCache()
    }

    /// Persists the default model preference.
    public func persistDefaultModel(_ model: ModelType) {
        persistenceHandler.persistDefaultModel(model)
    }

    /// Persists the default reasoning effort preference.
    public func persistDefaultEffort(_ effort: ReasoningEffort) {
        persistenceHandler.persistDefaultEffort(effort)
    }

    /// Persists the background mode toggle state.
    public func persistDefaultBackgroundModeEnabled(_ enabled: Bool) {
        persistenceHandler.persistDefaultBackgroundModeEnabled(enabled)
    }

    /// Persists the default service tier preference.
    public func persistDefaultServiceTier(_ serviceTier: ServiceTier) {
        persistenceHandler.persistDefaultServiceTier(serviceTier)
    }

    /// Persists the selected app theme.
    public func persistAppTheme(_ theme: AppTheme) {
        persistenceHandler.persistAppTheme(theme)
    }

    /// Persists the haptic feedback toggle state.
    public func persistHapticEnabled(_ enabled: Bool) {
        persistenceHandler.persistHapticEnabled(enabled)
    }

    /// Persists the Cloudflare gateway toggle state.
    public func persistCloudflareEnabled(_ enabled: Bool) {
        persistenceHandler.persistCloudflareEnabled(enabled)
    }
}
