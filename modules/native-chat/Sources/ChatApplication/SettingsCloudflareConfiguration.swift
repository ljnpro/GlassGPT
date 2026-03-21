import ChatDomain

/// The Cloudflare configuration currently selected or edited in the settings scene.
public struct SettingsCloudflareConfiguration: Equatable, Sendable {
    /// The selected configuration mode.
    public var mode: CloudflareGatewayConfigurationMode
    /// The custom gateway base URL being edited or persisted.
    public var customGatewayBaseURL: String
    /// The custom gateway token being edited or persisted.
    public var customGatewayToken: String

    /// Creates a settings-scoped Cloudflare configuration.
    public init(
        mode: CloudflareGatewayConfigurationMode,
        customGatewayBaseURL: String,
        customGatewayToken: String
    ) {
        self.mode = mode
        self.customGatewayBaseURL = customGatewayBaseURL
        self.customGatewayToken = customGatewayToken
    }
}
