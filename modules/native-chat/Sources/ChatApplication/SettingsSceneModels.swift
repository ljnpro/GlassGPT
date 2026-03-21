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
