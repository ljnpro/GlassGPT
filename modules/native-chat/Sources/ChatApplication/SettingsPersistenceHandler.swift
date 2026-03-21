import ChatDomain
import ChatPersistenceCore

/// Handler protocol for persisting user setting changes from the settings scene.
@MainActor
package protocol SettingsPersistenceHandler {
    /// Persists the default model preference.
    func persistDefaultModel(_ model: ModelType)
    /// Persists the default reasoning effort preference.
    func persistDefaultEffort(_ effort: ReasoningEffort)
    /// Persists the background mode toggle state.
    func persistDefaultBackgroundModeEnabled(_ enabled: Bool)
    /// Persists the default service tier preference.
    func persistDefaultServiceTier(_ serviceTier: ServiceTier)
    /// Persists the selected app theme.
    func persistAppTheme(_ theme: AppTheme)
    /// Persists the haptic feedback toggle state.
    func persistHapticEnabled(_ enabled: Bool)
    /// Persists the Cloudflare gateway toggle state.
    func persistCloudflareEnabled(_ enabled: Bool)
    /// Loads the persisted Cloudflare configuration mode.
    func loadCloudflareConfigurationMode() -> CloudflareGatewayConfigurationMode
    /// Loads the persisted custom Cloudflare gateway base URL.
    func loadCustomCloudflareGatewayBaseURL() -> String
    /// Loads the persisted custom Cloudflare gateway token.
    func loadCustomCloudflareGatewayToken() -> String?
    /// Persists the active Cloudflare configuration mode.
    func persistCloudflareConfigurationMode(_ mode: CloudflareGatewayConfigurationMode)
    /// Saves a custom Cloudflare gateway configuration and activates it.
    func saveCustomCloudflareConfiguration(
        gatewayBaseURL: String,
        gatewayToken: String
    ) throws(PersistenceError)
    /// Clears the saved custom Cloudflare gateway configuration.
    func clearCustomCloudflareConfiguration()
}
