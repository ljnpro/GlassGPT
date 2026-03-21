import ChatDomain
import ChatPersistenceCore
import Foundation

/// Identifies which generated-file cache the settings scene should operate on.
public enum SettingsGeneratedCacheKind: Sendable {
    /// The cache storing generated image downloads.
    case image
    /// The cache storing generated document and file downloads.
    case document
}

/// Snapshot of generated-file cache usage shown in settings.
public struct SettingsCacheSnapshot: Equatable, Sendable {
    /// Bytes currently used by the generated image cache.
    public let imageBytes: Int64
    /// Bytes currently used by the generated document cache.
    public let documentBytes: Int64

    /// Creates a cache usage snapshot.
    public init(imageBytes: Int64, documentBytes: Int64) {
        self.imageBytes = imageBytes
        self.documentBytes = documentBytes
    }
}

/// Result of saving an API key through the settings scene.
public struct SettingsAPIKeySaveOutcome: Equatable, Sendable {
    /// The trimmed API key that was persisted.
    public let apiKey: String
    /// The locally resolved Cloudflare health after the save, when gateway mode is enabled.
    public let cloudflareHealthStatus: CloudflareHealthStatus?

    /// Creates a save outcome.
    public init(apiKey: String, cloudflareHealthStatus: CloudflareHealthStatus?) {
        self.apiKey = apiKey
        self.cloudflareHealthStatus = cloudflareHealthStatus
    }
}

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

    /// Persists the given API key after trimming whitespace and resolves the new local Cloudflare state.
    ///
    /// - Parameters:
    ///   - typedAPIKey: The key currently entered in the UI.
    ///   - gatewayEnabled: Whether Cloudflare gateway routing is enabled.
    ///   - cloudflareConfiguration: The currently selected Cloudflare configuration.
    /// - Returns: A save outcome when the trimmed key is non-empty; otherwise `nil`.
    public func saveAPIKey(
        _ typedAPIKey: String,
        gatewayEnabled: Bool,
        cloudflareConfiguration: SettingsCloudflareConfiguration
    ) throws(PersistenceError) -> SettingsAPIKeySaveOutcome? {
        let trimmedKey = typedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        try credentialHandler.saveAPIKey(trimmedKey)
        let cloudflareHealthStatus = gatewayEnabled
            ? resolveCloudflareHealth(
                typedAPIKey: trimmedKey,
                gatewayEnabled: gatewayEnabled,
                configuration: cloudflareConfiguration
            )
            : nil
        return SettingsAPIKeySaveOutcome(
            apiKey: trimmedKey,
            cloudflareHealthStatus: cloudflareHealthStatus
        )
    }

    /// Removes the stored API key and resolves the resulting local Cloudflare state.
    public func clearAPIKey(
        gatewayEnabled: Bool,
        cloudflareConfiguration: SettingsCloudflareConfiguration
    ) -> CloudflareHealthStatus {
        credentialHandler.clearAPIKey()
        return resolveCloudflareHealth(
            typedAPIKey: "",
            gatewayEnabled: gatewayEnabled,
            configuration: cloudflareConfiguration
        )
    }

    /// Validates the API key against the OpenAI API.
    public func validateAPIKey(_ apiKey: String) async -> Bool {
        await credentialHandler.validateAPIKey(apiKey)
    }

    /// Loads the persisted Cloudflare configuration mode.
    public func loadCloudflareConfigurationMode() -> CloudflareGatewayConfigurationMode {
        persistenceHandler.loadCloudflareConfigurationMode()
    }

    /// Loads the persisted custom Cloudflare gateway base URL.
    public func loadCustomCloudflareGatewayBaseURL() -> String {
        persistenceHandler.loadCustomCloudflareGatewayBaseURL()
    }

    /// Loads the persisted custom Cloudflare gateway token.
    public func loadCustomCloudflareGatewayToken() -> String? {
        persistenceHandler.loadCustomCloudflareGatewayToken()
    }

    /// Persists the active Cloudflare configuration mode.
    public func persistCloudflareConfigurationMode(_ mode: CloudflareGatewayConfigurationMode) {
        persistenceHandler.persistCloudflareConfigurationMode(mode)
    }

    /// Saves a custom Cloudflare configuration and activates it.
    public func saveCustomCloudflareConfiguration(
        gatewayBaseURL: String,
        gatewayToken: String
    ) throws(PersistenceError) {
        try persistenceHandler.saveCustomCloudflareConfiguration(
            gatewayBaseURL: gatewayBaseURL,
            gatewayToken: gatewayToken
        )
    }

    /// Clears the custom Cloudflare configuration and returns to the default mode.
    public func clearCustomCloudflareConfiguration() {
        persistenceHandler.clearCustomCloudflareConfiguration()
    }

    /// Synchronously resolves the Cloudflare gateway health from local state.
    public func resolveCloudflareHealth(
        typedAPIKey: String,
        gatewayEnabled: Bool,
        configuration: SettingsCloudflareConfiguration
    ) -> CloudflareHealthStatus {
        credentialHandler.resolveCloudflareHealth(
            typedAPIKey: typedAPIKey,
            gatewayEnabled: gatewayEnabled,
            configuration: configuration
        )
    }

    /// Performs an async health check against the Cloudflare gateway.
    public func checkCloudflareHealth(
        typedAPIKey: String,
        gatewayEnabled: Bool,
        configuration: SettingsCloudflareConfiguration
    ) async -> CloudflareHealthStatus {
        await credentialHandler.checkCloudflareHealth(
            typedAPIKey: typedAPIKey,
            gatewayEnabled: gatewayEnabled,
            configuration: configuration
        )
    }

    /// Reads both generated-file cache buckets so the presenter can update one coherent snapshot.
    public func refreshGeneratedCacheSnapshot() async -> SettingsCacheSnapshot {
        let imageBytes = await cacheHandler.refreshGeneratedImageCacheSize()
        let documentBytes = await cacheHandler.refreshGeneratedDocumentCacheSize()
        return SettingsCacheSnapshot(
            imageBytes: imageBytes,
            documentBytes: documentBytes
        )
    }

    /// Clears one generated-file cache bucket and returns the resulting full snapshot.
    public func clearGeneratedCache(_ kind: SettingsGeneratedCacheKind) async -> SettingsCacheSnapshot {
        switch kind {
        case .image:
            _ = await cacheHandler.clearGeneratedImageCache()
        case .document:
            _ = await cacheHandler.clearGeneratedDocumentCache()
        }

        return await refreshGeneratedCacheSnapshot()
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
