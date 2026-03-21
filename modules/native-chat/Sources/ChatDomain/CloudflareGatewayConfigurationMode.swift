/// The persisted Cloudflare gateway configuration source for runtime routing.
public enum CloudflareGatewayConfigurationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Use the bundled or build-provided gateway configuration.
    case `default`
    /// Use a user-saved custom gateway URL and token.
    case custom

    /// Stable identifier derived from the raw value.
    public var id: String {
        rawValue
    }

    /// Human-readable name suitable for display in settings UI.
    public var displayName: String {
        switch self {
        case .default:
            "Default"
        case .custom:
            "Custom"
        }
    }
}
